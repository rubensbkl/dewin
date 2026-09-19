# Guia de Reversão e Rollback (DEWIN)

O projeto **DEWIN** foi desenhado sob o princípio de **reversibilidade total**. Nenhuma modificação destrói arquivos do sistema operacional ou substitui binários protegidos.

Caso você queira desfazer todas as alterações ou apenas um tweak específico, utilize as instruções abaixo.

---

## 1. Reversão Completa (Via Ponto de Restauração)

O script [`apply-dewin.ps1`](../scripts/apply-dewin.ps1) cria automaticamente um Ponto de Restauração chamado **`DEWIN-PreTweaks`** antes de executar qualquer alteração no sistema.

### Como Restaurar:
1. Pressione `Win + R`, digite `rstrui.exe` e pressione **Enter**.
2. Selecione **"Escolher um outro ponto de restauração"** e clique em **Avançar**.
3. Localize o ponto **`DEWIN-PreTweaks`** e clique em **Avançar** > **Concluir**.
4. O Windows reiniciará e restaurará o estado do registro e dos serviços exatamente como estavam antes da execução do script.

---

## 2. Reversão Cirúrgica por Componente

Se você quiser manter o sistema otimizado, mas desfazer apenas um ajuste individual, execute o comando correspondente no **PowerShell como Administrador**:

### A. Reativar a Hibernação
Caso você queira voltar a usar a função "Hibernar":
```powershell
powercfg.exe /hibernate on
```

### B. Restaurar o Menu de Contexto Moderno do Windows 11
Caso você prefira o novo menu de contexto com cantos arredondados:
```powershell
reg.exe delete "HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}" /f
taskkill /f /im explorer.exe; start explorer.exe
```

### C. Restaurar o TdrDelay Padrão da GPU (2 segundos)
Caso queira voltar aos valores padrão da Microsoft para o driver de vídeo:
```powershell
reg.exe delete "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" /v TdrDelay /f
reg.exe delete "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" /v TdrDdiDelay /f
```

### D. Reativar o Serviço DiagTrack (Telemetria)
Caso algum software de diagnóstico corporativo exija o serviço ativo:
```powershell
Set-Service -Name "DiagTrack" -StartupType Automatic
Start-Service -Name "DiagTrack"
```

### E. Reinstalar um Aplicativo Removido da Microsoft Store
Como a **Microsoft Store** foi preservada intacta, qualquer app que tenha sido removido durante o setup pode ser reinstalado diretamente da loja com 1 clique (ex: Bloco de Notas, Clipchamp, Clima, etc.) ou via Winget:
```powershell
# Exemplo para reinstalar o Clima:
winget install "MSN Weather"

# Exemplo para reinstalar o Bloco de Notas oficial:
winget install "Windows Notepad"
```

---

## 3. Verificação e Reparo de Integridade do Windows

Se você suspeitar que algum arquivo do sistema operacional foi corrompido ou precisa ser restaurado ao estado original de fábrica da Microsoft:

1. **Verificação de Componentes com DISM**:
   ```powershell
   DISM.exe /Online /Cleanup-image /Restorehealth
   ```
2. **Verificação de Arquivos Protegidos com SFC**:
   ```powershell
   sfc /scannow
   ```
3. Reinicie o computador após a conclusão.
