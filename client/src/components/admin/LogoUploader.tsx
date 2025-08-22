import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { Upload, Image, X } from 'lucide-react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { apiRequest } from '@/lib/queryClient';
import { useToast } from '@/hooks/use-toast';

interface LogoUploaderProps {
  title: string;
  currentLogo?: string | null;
  uploadEndpoint: string;
  onSuccess?: () => void;
  type: 'system' | 'tenant';
  entityId?: string;
}

export function LogoUploader({ 
  title, 
  currentLogo, 
  uploadEndpoint, 
  onSuccess, 
  type, 
  entityId 
}: LogoUploaderProps) {
  const [selectedFile, setSelectedFile] = useState<File | null>(null);
  const [previewUrl, setPreviewUrl] = useState<string | null>(null);
  const { toast } = useToast();
  const queryClient = useQueryClient();

  const uploadMutation = useMutation({
    mutationFn: async (file: File) => {
      // Get upload URL
      const uploadResponse = await apiRequest('POST', '/api/objects/upload');
      const { uploadURL } = await uploadResponse.json();

      // Upload file to object storage
      const formData = new FormData();
      formData.append('file', file);

      const uploadResult = await fetch(uploadURL, {
        method: 'PUT',
        body: file,
        headers: {
          'Content-Type': file.type,
        },
      });

      if (!uploadResult.ok) {
        throw new Error('Failed to upload file');
      }

      // Update system/tenant with logo URL
      const updateData = type === 'system' 
        ? { logoUrl: uploadURL.split('?')[0] }
        : { logoUrl: uploadURL.split('?')[0] };

      const updateResponse = await apiRequest('PUT', uploadEndpoint, updateData);
      return await updateResponse.json();
    },
    onSuccess: () => {
      toast({
        title: 'Logo atualizado',
        description: 'O logo foi carregado com sucesso.',
      });
      setSelectedFile(null);
      setPreviewUrl(null);
      queryClient.invalidateQueries({ queryKey: ['/api/admin/settings'] });
      queryClient.invalidateQueries({ queryKey: ['/api/admin/tenants'] });
      onSuccess?.();
    },
    onError: (error: Error) => {
      toast({
        title: 'Erro no upload',
        description: error.message,
        variant: 'destructive',
      });
    },
  });

  const handleFileSelect = (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.target.files?.[0];
    if (!file) return;

    // Validate file type
    if (!file.type.startsWith('image/')) {
      toast({
        title: 'Arquivo inválido',
        description: 'Por favor, selecione um arquivo de imagem.',
        variant: 'destructive',
      });
      return;
    }

    // Validate file size (max 5MB)
    if (file.size > 5 * 1024 * 1024) {
      toast({
        title: 'Arquivo muito grande',
        description: 'O arquivo deve ter no máximo 5MB.',
        variant: 'destructive',
      });
      return;
    }

    setSelectedFile(file);
    
    // Create preview
    const reader = new FileReader();
    reader.onload = (e) => {
      setPreviewUrl(e.target?.result as string);
    };
    reader.readAsDataURL(file);
  };

  const handleUpload = () => {
    if (selectedFile) {
      uploadMutation.mutate(selectedFile);
    }
  };

  const handleCancel = () => {
    setSelectedFile(null);
    setPreviewUrl(null);
  };

  return (
    <Card>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <Image className="w-5 h-5" />
          {title}
        </CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        {/* Current Logo */}
        {currentLogo && !previewUrl && (
          <div className="flex items-center justify-center p-4 border rounded-lg bg-muted">
            <img
              src={currentLogo}
              alt="Logo atual"
              className="max-h-20 max-w-full object-contain"
            />
          </div>
        )}

        {/* Preview */}
        {previewUrl && (
          <div className="space-y-2">
            <div className="flex items-center justify-center p-4 border rounded-lg bg-muted">
              <img
                src={previewUrl}
                alt="Preview"
                className="max-h-20 max-w-full object-contain"
              />
            </div>
            <div className="flex gap-2">
              <Button
                onClick={handleUpload}
                disabled={uploadMutation.isPending}
                className="flex-1"
                data-testid="button-upload-logo"
              >
                {uploadMutation.isPending ? 'Enviando...' : 'Confirmar Upload'}
              </Button>
              <Button
                variant="outline"
                onClick={handleCancel}
                disabled={uploadMutation.isPending}
                data-testid="button-cancel-upload"
              >
                <X className="w-4 h-4" />
              </Button>
            </div>
          </div>
        )}

        {/* File Input */}
        {!previewUrl && (
          <div className="space-y-2">
            <input
              type="file"
              accept="image/*"
              onChange={handleFileSelect}
              className="hidden"
              id={`logo-upload-${type}-${entityId || 'system'}`}
            />
            <label
              htmlFor={`logo-upload-${type}-${entityId || 'system'}`}
              className="flex flex-col items-center justify-center p-6 border-2 border-dashed border-muted-foreground/25 rounded-lg cursor-pointer hover:border-muted-foreground/50 transition-colors"
            >
              <Upload className="w-8 h-8 text-muted-foreground mb-2" />
              <span className="text-sm text-muted-foreground text-center">
                Clique para selecionar uma imagem<br />
                <span className="text-xs">PNG, JPG até 5MB</span>
              </span>
            </label>
          </div>
        )}
      </CardContent>
    </Card>
  );
}