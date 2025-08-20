// SamurEye External Scanner Service
// Serviço dedicado para scanner.samureye.com.br (porta 3001)

const express = require('express');
const { spawn } = require('child_process');
const fs = require('fs').promises;
const path = require('path');
const crypto = require('crypto');

const app = express();
const PORT = process.env.SCANNER_PORT || 3001;

app.use(express.json({ limit: '10mb' }));

// Middleware de logging
app.use((req, res, next) => {
  console.log(`[${new Date().toISOString()}] ${req.method} ${req.path} - ${req.ip}`);
  next();
});

// Health check
app.get('/health', (req, res) => {
  res.json({ 
    status: 'ok', 
    service: 'samureye-scanner',
    timestamp: new Date().toISOString(),
    version: '1.0.0'
  });
});

// Validar API key (implementar autenticação apropriada)
const validateApiKey = (req, res, next) => {
  const apiKey = req.headers['x-api-key'];
  const validApiKey = process.env.SCANNER_API_KEY || 'your-secure-api-key';
  
  if (!apiKey || apiKey !== validApiKey) {
    return res.status(401).json({ error: 'Unauthorized: Invalid API key' });
  }
  
  next();
};

// Endpoint para scan de Attack Surface com Nmap
app.post('/api/scan/attack-surface', validateApiKey, async (req, res) => {
  try {
    const { targets, options = {}, journeyId } = req.body;
    
    if (!targets || !Array.isArray(targets) || targets.length === 0) {
      return res.status(400).json({ error: 'Targets array is required' });
    }

    const scanId = crypto.randomUUID();
    const timestamp = new Date().toISOString();
    
    console.log(`Starting Attack Surface scan ${scanId} for journey ${journeyId}`);
    
    // Configurações padrão do Nmap
    const nmapArgs = [
      '-sS', // SYN scan
      '-sV', // Version detection
      '-O',  // OS detection
      '--script=default,vuln',
      '--max-retries=1',
      '--host-timeout=300s',
      '-oX', `/tmp/nmap_${scanId}.xml`,
      ...targets
    ];

    // Aplicar opções customizadas
    if (options.aggressive) {
      nmapArgs.push('-A');
    }
    if (options.ports) {
      nmapArgs.push('-p', options.ports);
    }
    if (options.timing) {
      nmapArgs.push(`-T${options.timing}`);
    }

    // Executar Nmap
    const nmapProcess = spawn('nmap', nmapArgs);
    let nmapOutput = '';
    let nmapError = '';

    nmapProcess.stdout.on('data', (data) => {
      nmapOutput += data.toString();
    });

    nmapProcess.stderr.on('data', (data) => {
      nmapError += data.toString();
    });

    nmapProcess.on('close', async (code) => {
      try {
        let results = {
          scanId,
          journeyId,
          timestamp,
          command: `nmap ${nmapArgs.join(' ')}`,
          exitCode: code,
          output: nmapOutput,
          error: nmapError
        };

        // Ler arquivo XML se disponível
        try {
          const xmlContent = await fs.readFile(`/tmp/nmap_${scanId}.xml`, 'utf8');
          results.xmlOutput = xmlContent;
          
          // Parse básico do XML para extrair informações importantes
          results.summary = parseNmapXML(xmlContent);
          
          // Cleanup
          await fs.unlink(`/tmp/nmap_${scanId}.xml`).catch(() => {});
        } catch (xmlError) {
          console.warn(`Could not read XML output: ${xmlError.message}`);
        }

        console.log(`Attack Surface scan ${scanId} completed with exit code ${code}`);
        
        // Se há um journeyId, enviar resultados de volta para a API principal
        if (journeyId) {
          await sendResultsToMainAPI(journeyId, results);
        }

        res.json(results);
      } catch (error) {
        console.error(`Error processing scan results: ${error.message}`);
        res.status(500).json({ error: 'Error processing scan results' });
      }
    });

    // Timeout de 30 minutos
    setTimeout(() => {
      if (nmapProcess.pid) {
        nmapProcess.kill('SIGTERM');
        console.log(`Scan ${scanId} timed out after 30 minutes`);
      }
    }, 30 * 60 * 1000);

  } catch (error) {
    console.error(`Scan error: ${error.message}`);
    res.status(500).json({ error: 'Internal server error during scan' });
  }
});

// Endpoint para scan com Nuclei
app.post('/api/scan/nuclei', validateApiKey, async (req, res) => {
  try {
    const { targets, templates = [], options = {}, journeyId } = req.body;
    
    if (!targets || !Array.isArray(targets) || targets.length === 0) {
      return res.status(400).json({ error: 'Targets array is required' });
    }

    const scanId = crypto.randomUUID();
    const timestamp = new Date().toISOString();
    
    console.log(`Starting Nuclei scan ${scanId} for journey ${journeyId}`);
    
    // Criar arquivo temporário com targets
    const targetsFile = `/tmp/nuclei_targets_${scanId}.txt`;
    await fs.writeFile(targetsFile, targets.join('\n'));
    
    // Configurações do Nuclei
    const nucleiArgs = [
      '-l', targetsFile,
      '-j', // JSON output
      '-o', `/tmp/nuclei_${scanId}.json`,
      '-stats',
      '-silent'
    ];

    // Aplicar templates específicos
    if (templates.length > 0) {
      nucleiArgs.push('-t', templates.join(','));
    } else {
      nucleiArgs.push('-t', 'cves,vulnerabilities,exposures');
    }

    // Aplicar opções
    if (options.severity) {
      nucleiArgs.push('-severity', options.severity);
    }
    if (options.concurrency) {
      nucleiArgs.push('-c', options.concurrency.toString());
    }

    // Executar Nuclei
    const nucleiProcess = spawn('nuclei', nucleiArgs);
    let nucleiOutput = '';
    let nucleiError = '';

    nucleiProcess.stdout.on('data', (data) => {
      nucleiOutput += data.toString();
    });

    nucleiProcess.stderr.on('data', (data) => {
      nucleiError += data.toString();
    });

    nucleiProcess.on('close', async (code) => {
      try {
        let results = {
          scanId,
          journeyId,
          timestamp,
          command: `nuclei ${nucleiArgs.join(' ')}`,
          exitCode: code,
          output: nucleiOutput,
          error: nucleiError
        };

        // Ler resultados JSON
        try {
          const jsonContent = await fs.readFile(`/tmp/nuclei_${scanId}.json`, 'utf8');
          const findings = jsonContent.split('\n')
            .filter(line => line.trim())
            .map(line => JSON.parse(line));
          
          results.findings = findings;
          results.summary = {
            totalFindings: findings.length,
            severityBreakdown: findings.reduce((acc, finding) => {
              const severity = finding.info?.severity || 'unknown';
              acc[severity] = (acc[severity] || 0) + 1;
              return acc;
            }, {})
          };
          
          // Cleanup
          await fs.unlink(`/tmp/nuclei_${scanId}.json`).catch(() => {});
        } catch (jsonError) {
          console.warn(`Could not read JSON output: ${jsonError.message}`);
        }

        // Cleanup targets file
        await fs.unlink(targetsFile).catch(() => {});

        console.log(`Nuclei scan ${scanId} completed with exit code ${code}`);
        
        // Enviar resultados para API principal
        if (journeyId) {
          await sendResultsToMainAPI(journeyId, results);
        }

        res.json(results);
      } catch (error) {
        console.error(`Error processing Nuclei results: ${error.message}`);
        res.status(500).json({ error: 'Error processing scan results' });
      }
    });

    // Timeout de 45 minutos
    setTimeout(() => {
      if (nucleiProcess.pid) {
        nucleiProcess.kill('SIGTERM');
        console.log(`Nuclei scan ${scanId} timed out after 45 minutes`);
      }
    }, 45 * 60 * 1000);

  } catch (error) {
    console.error(`Nuclei scan error: ${error.message}`);
    res.status(500).json({ error: 'Internal server error during scan' });
  }
});

// Parse básico do XML do Nmap
function parseNmapXML(xmlContent) {
  const summary = {
    hostsUp: 0,
    hostsDown: 0,
    totalPorts: 0,
    openPorts: 0,
    services: [],
    vulnerabilities: []
  };

  try {
    // Parse básico sem dependências externas
    const hostUpMatches = xmlContent.match(/<host.*?endtime=/g);
    if (hostUpMatches) {
      summary.hostsUp = hostUpMatches.length;
    }

    const portMatches = xmlContent.match(/<port.*?state="open"/g);
    if (portMatches) {
      summary.openPorts = portMatches.length;
    }

    const serviceMatches = xmlContent.match(/<service.*?name="([^"]+)"/g);
    if (serviceMatches) {
      summary.services = [...new Set(serviceMatches.map(match => {
        const nameMatch = match.match(/name="([^"]+)"/);
        return nameMatch ? nameMatch[1] : '';
      }).filter(Boolean))];
    }
  } catch (error) {
    console.warn(`Error parsing Nmap XML: ${error.message}`);
  }

  return summary;
}

// Enviar resultados para a API principal
async function sendResultsToMainAPI(journeyId, results) {
  try {
    const apiEndpoint = process.env.MAIN_API_ENDPOINT || 'http://172.24.1.152:3000';
    const apiKey = process.env.MAIN_API_KEY || process.env.SCANNER_API_KEY;
    
    const response = await fetch(`${apiEndpoint}/api/journeys/${journeyId}/results`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-API-Key': apiKey
      },
      body: JSON.stringify({
        source: 'external-scanner',
        results
      })
    });

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${response.statusText}`);
    }

    console.log(`Results successfully sent to main API for journey ${journeyId}`);
  } catch (error) {
    console.error(`Failed to send results to main API: ${error.message}`);
  }
}

// Error handling
app.use((error, req, res, next) => {
  console.error(`Unhandled error: ${error.message}`);
  res.status(500).json({ error: 'Internal server error' });
});

// 404 handler
app.use('*', (req, res) => {
  res.status(404).json({ error: 'Not found' });
});

// Graceful shutdown
process.on('SIGTERM', () => {
  console.log('Received SIGTERM, shutting down gracefully');
  process.exit(0);
});

process.on('SIGINT', () => {
  console.log('Received SIGINT, shutting down gracefully');
  process.exit(0);
});

app.listen(PORT, '0.0.0.0', () => {
  console.log(`SamurEye Scanner Service running on port ${PORT}`);
  console.log(`Environment: ${process.env.NODE_ENV || 'development'}`);
});