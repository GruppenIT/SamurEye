import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Badge } from '@/components/ui/badge';
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table';
import { Plus, Edit, Trash2, Key, Shield, FileText } from 'lucide-react';
import { CredentialForm } from '@/components/credentials/CredentialForm';
import { apiRequest } from '@/lib/queryClient';
import { useToast } from '@/hooks/use-toast';
import { formatDistanceToNow } from 'date-fns';
import { ptBR } from 'date-fns/locale';

interface Credential {
  id: string;
  name: string;
  type: string;
  description?: string;
  credentialData: Record<string, any>;
  isActive: boolean;
  createdAt: string;
  updatedAt: string;
}

export default function Credentials() {
  const { toast } = useToast();
  const queryClient = useQueryClient();
  const [showForm, setShowForm] = useState(false);
  const [editingCredential, setEditingCredential] = useState<Credential | null>(null);

  const { data: credentials = [], isLoading } = useQuery<Credential[]>({
    queryKey: ['/api/credentials'],
  });

  const deleteMutation = useMutation({
    mutationFn: async (id: string) => {
      await apiRequest('DELETE', `/api/credentials/${id}`);
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['/api/credentials'] });
      toast({
        title: 'Sucesso',
        description: 'Credencial removida com sucesso',
      });
    },
    onError: (error: any) => {
      toast({
        title: 'Erro',
        description: error.message || 'Erro ao remover credencial',
        variant: 'destructive',
      });
    },
  });

  const handleEdit = (credential: Credential) => {
    setEditingCredential(credential);
    setShowForm(true);
  };

  const handleDelete = (id: string) => {
    if (confirm('Tem certeza que deseja remover esta credencial?')) {
      deleteMutation.mutate(id);
    }
  };

  const handleCloseForm = () => {
    setShowForm(false);
    setEditingCredential(null);
  };

  const getTypeIcon = (type: string) => {
    switch (type) {
      case 'ssh':
        return <Key className="h-4 w-4" />;
      case 'ldap':
        return <Shield className="h-4 w-4" />;
      case 'database':
        return <FileText className="h-4 w-4" />;
      default:
        return <Key className="h-4 w-4" />;
    }
  };

  const getTypeBadgeColor = (type: string) => {
    switch (type) {
      case 'ssh':
        return 'bg-blue-500';
      case 'ldap':
        return 'bg-green-500';
      case 'database':
        return 'bg-purple-500';
      case 'snmp':
        return 'bg-orange-500';
      case 'http':
      case 'https':
        return 'bg-red-500';
      case 'wmi':
        return 'bg-yellow-500';
      default:
        return 'bg-gray-500';
    }
  };

  const getCredentialSummary = (credential: Credential) => {
    const data = credential.credentialData;
    switch (credential.type) {
      case 'ssh':
        return `${data.username}@${data.hostname}:${data.port || 22}`;
      case 'ldap':
        return `${data.hostname}:${data.port || 389} (${data.bindDn})`;
      case 'database':
        return `${data.hostname}:${data.port || 5432}/${data.database}`;
      case 'http':
      case 'https':
        return data.url;
      case 'snmp':
        return `${data.hostname}:${data.port || 161} (v${data.version})`;
      case 'wmi':
        return `${data.hostname} (${data.domain || 'local'})`;
      default:
        return 'Configuração personalizada';
    }
  };

  if (isLoading) {
    return (
      <div className="flex items-center justify-center h-32">
        <div className="text-sm text-muted-foreground">Carregando credenciais...</div>
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <div>
          <h1 className="text-3xl font-bold">Credenciais</h1>
          <p className="text-muted-foreground">
            Gerencie credenciais para acesso aos sistemas alvo
          </p>
        </div>
        <Button onClick={() => setShowForm(true)} data-testid="button-new-credential">
          <Plus className="h-4 w-4 mr-2" />
          Nova Credencial
        </Button>
      </div>

      {credentials.length === 0 ? (
        <Card>
          <CardContent className="py-8">
            <div className="text-center">
              <Key className="h-12 w-12 mx-auto text-muted-foreground mb-4" />
              <h3 className="text-lg font-medium mb-2">Nenhuma credencial encontrada</h3>
              <p className="text-muted-foreground mb-4">
                Crie sua primeira credencial para começar a usar o sistema
              </p>
              <Button onClick={() => setShowForm(true)}>
                <Plus className="h-4 w-4 mr-2" />
                Criar Credencial
              </Button>
            </div>
          </CardContent>
        </Card>
      ) : (
        <Card>
          <CardHeader>
            <CardTitle>Credenciais Cadastradas</CardTitle>
          </CardHeader>
          <CardContent>
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Nome</TableHead>
                  <TableHead>Tipo</TableHead>
                  <TableHead>Configuração</TableHead>
                  <TableHead>Status</TableHead>
                  <TableHead>Atualizada</TableHead>
                  <TableHead>Ações</TableHead>
                </TableRow>
              </TableHeader>
              <TableBody>
                {credentials.map((credential) => (
                  <TableRow key={credential.id}>
                    <TableCell>
                      <div className="flex items-center gap-2">
                        {getTypeIcon(credential.type)}
                        <div>
                          <div className="font-medium">{credential.name}</div>
                          {credential.description && (
                            <div className="text-sm text-muted-foreground">
                              {credential.description}
                            </div>
                          )}
                        </div>
                      </div>
                    </TableCell>
                    <TableCell>
                      <Badge 
                        className={`${getTypeBadgeColor(credential.type)} text-white`}
                        data-testid={`badge-type-${credential.type}`}
                      >
                        {credential.type.toUpperCase()}
                      </Badge>
                    </TableCell>
                    <TableCell>
                      <div className="text-sm font-mono">
                        {getCredentialSummary(credential)}
                      </div>
                    </TableCell>
                    <TableCell>
                      <Badge 
                        variant={credential.isActive ? 'default' : 'secondary'}
                        data-testid={`status-${credential.id}`}
                      >
                        {credential.isActive ? 'Ativa' : 'Inativa'}
                      </Badge>
                    </TableCell>
                    <TableCell>
                      <div className="text-sm text-muted-foreground">
                        {formatDistanceToNow(new Date(credential.updatedAt), {
                          addSuffix: true,
                          locale: ptBR,
                        })}
                      </div>
                    </TableCell>
                    <TableCell>
                      <div className="flex gap-2">
                        <Button
                          size="sm"
                          variant="outline"
                          onClick={() => handleEdit(credential)}
                          data-testid={`button-edit-${credential.id}`}
                        >
                          <Edit className="h-4 w-4" />
                        </Button>
                        <Button
                          size="sm"
                          variant="outline"
                          onClick={() => handleDelete(credential.id)}
                          disabled={deleteMutation.isPending}
                          data-testid={`button-delete-${credential.id}`}
                        >
                          <Trash2 className="h-4 w-4" />
                        </Button>
                      </div>
                    </TableCell>
                  </TableRow>
                ))}
              </TableBody>
            </Table>
          </CardContent>
        </Card>
      )}

      <CredentialForm
        open={showForm}
        onClose={handleCloseForm}
        credential={editingCredential}
      />
    </div>
  );
}