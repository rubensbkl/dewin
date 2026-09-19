# Integração WinUtil (Perfis DEWIN)

Configurações exportadas para o utilitário **Chris Titus Tech Windows Utility (WinUtil)**, calibradas para estações de trabalho e jogos.

---

## 1. Perfis Disponíveis

1. **[`dewin-full.json`](dewin-full.json)** (ou `dewin.json`):
   * Perfil completo com tweaks de sistema, runtimes VC++, Chrome, 7-Zip e virtualização (**WSL2**, **Hyper-V** e **Windows Sandbox**).
2. **[`dewin-creator.json`](dewin-creator.json)**:
   * Perfil focado em criação de conteúdo (vídeo/3D) e jogos. Aplica todos os tweaks de sistema e runtimes, sem ativar virtualização Linux/Hyper-V.

---

## 2. Inventário de Tweaks e Pacotes (`dewin-full.json`)

| Identificador no JSON | Ação Executada | Justificativa |
| :--- | :--- | :--- |
| `WPFTweaksRestorePoint` | Cria Ponto de Restauração inicial | Garante reversibilidade antes de aplicar tweaks. |
| `WPFTweaksTelemetry` | Desativa DiagTrack e tarefas de telemetria | Redução de processos e requisições em segundo plano. |
| `WPFTweaksActivity` | Desativa histórico de atividades | Evita envio de metadados para a nuvem. |
| `WPFTweaksLocation` | Desativa geolocalização do Windows | Desnecessário para computadores desktop. |
| `WPFTweaksHiber` | Desativa hibernação | Libera de 16 a 24 GB de espaço em SSD. |
| `WPFTweaksDeliveryOptimization` | Desativa upload P2P do Windows Update | Impede uso de banda de upload para terceiros. |
| `WPFTweaksDisableExplorerAutoDiscovery` | Desativa descoberta de tipo de pasta | Pastas com assets de mídia abrem instantaneamente. |
| `WPFTweaksDisableStoreSearch` | Remove anúncios na busca local | Busca local mais rápida e limpa. |
| `WPFTweaksDiskCleanup` | Limpeza de disco nativa | Remove arquivos temporários de setup. |
| `WPFTweaksDeleteTempFiles` | Limpeza de pastas `%TEMP%` | Remoção de cache e arquivos descartáveis. |
| `WPFTweaksServices` | Altera serviços secundários para Manual | Reduz processos em idle sem quebrar dependências. |
| `WPFTweaksReservedStorage` | Desativa armazenamento reservado | Libera ~7 GB adicionais no disco. |
| `WPFTweaksWindowsAI` | Remove telemetria de assistentes de IA | Economia de CPU e privacidade. |
| `WPFTweaksRazerBlock` | Bloqueia instalador de periféricos Razer | Previne instalação automática do Razer Synapse ao plugar mouse. |
| `WPFToggleDetailedBSoD` | Ativa tela azul detalhada (Verbose BSoD) | Exibe o driver exato da falha para diagnóstico. |
| `WPFInstallchrome` | Instalação do Google Chrome | Navegador padrão. |
| `WPFInstall7zip` | Instalação do utilitário 7-Zip | Descompactador de alta performance. |
| `WPFInstallvc2015_64` | Visual C++ 2015-2022 x64 | Runtimes de 64-bits. |
| `WPFInstallvc2015_32` | Visual C++ 2015-2022 x86 (32-bit) | Compatibilidade com plugins e jogos legados. |
| `WPFFeaturewsl` | Habilita WSL | Subsistema Linux nativo. |
| `WPFFeatureshyperv` | Habilita Hyper-V | Hipervisor para Docker Desktop e VMs. |
| `WPFFeaturesSandbox` | Habilita Windows Sandbox | Ambiente descartável para testes de segurança. |

---

## 3. O que foi mantido desmarcado

* **`Adobe URL Block List`**: Quebraria a autenticação e atualizações da Adobe Creative Cloud.
* **`IPv6 - Disable` / `Teredo - Disable`**: Quebraria o matchmaking em jogos multiplayer e conexões modernas.
* **`Visual Effects - Set to Best Performance`**: Removeria fontes suaves e miniaturas de fotos/vídeos.
* **`Ultimate Performance Profile`**: Prejudicaria o boost térmico de processadores modernos AMD/Intel.

---

## 4. Como Executar

### Via Script de Automação (Recomendado)
Execute no PowerShell como Administrador:
```powershell
.\scripts\apply-dewin.ps1
```

### Manualmente pelo WinUtil
1. Execute no PowerShell:
   ```powershell
   irm "https://christitus.com/win" | iex
   ```
2. Clique na engrenagem ⚙️ no canto superior direito.
3. Selecione `Import Configuration` e escolha o arquivo `dewin-full.json` ou `dewin-creator.json`.
4. Clique em `Run Tweaks`.
