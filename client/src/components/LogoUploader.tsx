import { useState } from "react";
import { ObjectUploader } from "./ObjectUploader";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Upload, Image as ImageIcon } from "lucide-react";
import { apiRequest } from "@/lib/queryClient";
import { useToast } from "@/hooks/use-toast";
import type { UploadResult } from "@uppy/core";

interface LogoUploaderProps {
  title: string;
  description: string;
  currentLogoUrl?: string;
  onLogoUpdate: (logoUrl: string) => void;
  type: "global" | "tenant";
  tenantId?: string;
}

export function LogoUploader({ 
  title, 
  description, 
  currentLogoUrl, 
  onLogoUpdate, 
  type,
  tenantId 
}: LogoUploaderProps) {
  const { toast } = useToast();
  const [uploading, setUploading] = useState(false);

  const handleGetUploadParameters = async () => {
    const response = await apiRequest("/api/objects/upload", "POST");
    return {
      method: "PUT" as const,
      url: response.uploadURL,
    };
  };

  const handleComplete = async (result: UploadResult<Record<string, unknown>, Record<string, unknown>>) => {
    try {
      setUploading(true);
      
      if (result.successful.length === 0) {
        throw new Error("Upload failed");
      }

      const uploadedFile = result.successful[0];
      const logoURL = uploadedFile.uploadURL;

      // Set logo in system/tenant
      const endpoint = type === "global" 
        ? "/api/admin/system-logo"
        : `/api/tenants/${tenantId}/logo`;
        
      await apiRequest(endpoint, "PUT", { logoURL });

      onLogoUpdate(logoURL);
      toast({
        title: "Sucesso",
        description: "Logo atualizado com sucesso",
      });
    } catch (error) {
      console.error("Error updating logo:", error);
      toast({
        title: "Erro",
        description: "Falha ao atualizar logo",
        variant: "destructive",
      });
    } finally {
      setUploading(false);
    }
  };

  return (
    <Card data-testid={`card-logo-${type}`}>
      <CardHeader>
        <CardTitle className="flex items-center gap-2">
          <ImageIcon className="h-5 w-5" />
          {title}
        </CardTitle>
        <CardDescription>{description}</CardDescription>
      </CardHeader>
      <CardContent className="space-y-4">
        {currentLogoUrl && (
          <div className="border rounded-lg p-4 bg-muted/50">
            <img 
              src={currentLogoUrl} 
              alt="Logo atual" 
              className="h-16 w-auto object-contain"
              data-testid={`img-current-logo-${type}`}
            />
          </div>
        )}
        
        <ObjectUploader
          maxNumberOfFiles={1}
          maxFileSize={5 * 1024 * 1024} // 5MB
          onGetUploadParameters={handleGetUploadParameters}
          onComplete={handleComplete}
          buttonClassName="w-full"
        >
          <Upload className="mr-2 h-4 w-4" />
          {uploading ? "Enviando..." : currentLogoUrl ? "Alterar Logo" : "Fazer Upload do Logo"}
        </ObjectUploader>
      </CardContent>
    </Card>
  );
}