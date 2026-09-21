# Integração WinUtil (Perfis DEWIN)

Configurações exportadas para o utilitário **Chris Titus Tech Windows Utility (WinUtil)**, calibradas para estações de trabalho e notebooks através da **Matriz 2x2 DEWIN**.

---

## 1. Matriz de Perfis Disponíveis

| Hardware | Finalidade Dev / Workstation | Finalidade Geral / Produtividade |
| :--- | :--- | :--- |
| **Desktop** | **[`dewin-desktop-dev.json`](dewin-desktop-dev.json)**<br>WSL2 + Hyper-V + Sandbox + Sem Hibernação | **[`dewin-desktop-geral.json`](dewin-desktop-geral.json)**<br>Máxima leveza + Sem Virtualização + Sem Hibernação |
| **Notebook** | **[`dewin-laptop-dev.json`](dewin-laptop-dev.json)**<br>*(ex: Acer Nitro V 15)*<br>WSL2 + Hyper-V + **Hibernação Segura (Bateria)** | **[`dewin-laptop-geral.json`](dewin-laptop-geral.json)**<br>*(ex: ASUS VivoBook 14/15)*<br>Autonomia máxima + Sem Virtualização + **Hibernação Segura** |

---

## 2. Diferenças Chave entre Perfis

* **Desktops (`dewin-desktop-*.json`)**:
  * Incluem `WPFTweaksHiber`: Desativa a hibernação para liberar de 16 a 24 GB de espaço em SSD NVMe.
* **Notebooks (`dewin-laptop-*.json`)**:
  * **NÃO** desativam a hibernação no WinUtil. O script DEWIN calibra automaticamente para o modo reduzido (`powercfg /h /type reduced`), ocupando apenas ~3 GB. Isso garante segurança contra desligamento súbito em bateria crítica (< 3%) e suspensão segura sem superaquecimento dentro da mochila (Modern Standby).
* **Perfis Dev (`*-dev.json`)**:
  * Ativam `WPFFeaturewsl`, `WPFFeatureshyperv` e `WPFFeaturesSandbox` para suporte nativo a Docker Desktop e Linux.
* **Perfis Geral (`*-geral.json`)**:
  * Não ativam hipervisores, economizando de 1.5 a 2 GB de RAM em segundo plano e garantindo máxima autonomia e performance para softwares criativos, escritório e jogos.

---

## 3. Inventário Completo de Tweaks e Pacotes

| Identificador no JSON | Ação Executada | Justificativa |
| :--- | :--- | :--- |
| `WPFTweaksRestorePoint` | Cria Ponto de Restauração inicial | Garante reversibilidade antes de aplicar tweaks. |
| `WPFTweaksTelemetry` | Desativa DiagTrack e tarefas de telemetria | Redução de processos e requisições em segundo plano. |
| `WPFTweaksActivity` | Desativa histórico de atividades | Evita envio de metadados para a nuvem. |
| `WPFTweaksLocation` | Desativa geolocalização do Windows | Desnecessário para computadores desktop/estações. |
| `WPFTweaksHiber` | Desativa hibernação *(Apenas Desktops)* | Libera de 16 a 24 GB de espaço em SSD. |
| `WPFTweaksDeliveryOptimization` | Desativa upload P2P do Windows Update | Impede uso de banda de upload para terceiros. |
| `WPFTweaksDisableExplorerAutoDiscovery` | Desativa descoberta de tipo de pasta | Pastas com assets de mídia abrem instantaneamente. |
| `WPFTweaksDisableStoreSearch` | Remove anúncios na busca local | Busca local mais rápida e limpa. |
| `WPFTweaksDiskCleanup` | Limpeza de disco nativa | Remove arquivos temporários de setup. |
| `WPFTweaksDeleteTempFiles` | Limpeza de pastas `%TEMP%` | Remoção de cache e arquivos descartáveis. |
| `WPFTweaksServices` | Altera serviços secundários para Manual | Reduz processos em idle sem quebrar dependências. |
| `WPFTweaksReservedStorage` | Desativa armazenamento reservado | Libera ~7 GB adicionais no disco. |
| `WPFTweaksWindowsAI` | Remove telemetria de assistentes de IA | Economia de CPU e privacidade. |
| `WPFTweaksRazerBlock` | Bloqueia instalador de periféricos Razer | Previne instalação automática do Razer Synapse ao plugar mouse. |
| `WPFTweaksWPBT` | Bloqueia injeção de firmware WPBT | Impede injeção do Asus Armoury Crate via placa-mãe. |
| `WPFTweaksEndTaskOnTaskbar` | Habilita "Finalizar Tarefa" na barra | Fecha programas travados com 2 cliques na barra de tarefas. |
| `WPFTweaksConsumerFeatures` | Bloqueia Consumer Features | Impede instalação automática de jogos e apps patrocinados. |
| `WPFTweaksPreventDeviceMetadataFromNetwork` | Bloqueia Device Companion Apps | Impede instalação de apps automáticos de monitores/mouses. |
| `WPFTweaksWidget` | Remove Widgets do Windows | Elimina feeds de notícias e consumo de RAM do `Widgets.exe`. |
| `WPFTweaksRightClickMenu` | Restaura Menu de Contexto Clássico | Menu estilo Windows 10 sem cliques extras no Windows 11. |
| `WPFTweaksRemoveOneDrive` | Remove Microsoft OneDrive | Desinstalação completa do OneDrive e desativação do serviço de sincronização `OneSyncSvc`. |
| `WPFTweaksLogiBlock` | Bloqueia Logi Download Assistant | Previne injeção automática de software da Logitech via Windows Update. |
| `WPFTweaksRemoveHomeAndGallery` | Remove Início e Galeria do Explorer | Abre o Explorer diretamente em "Este Computador" (`LaunchTo = 1`) e limpa o painel lateral. |
| `WPFTweaksEdgeDebloat` | Debloat do Microsoft Edge | Desativa telemetria, popups promocionais, cupons e assistentes do Edge (mantém o WebView2). |
| `WPFTweaksDisableWarningForUnsignedRdp` | Desativa aviso em conexões RDP | *(Apenas Dev)* Elimina avisos repetitivos ao abrir arquivos `.rdp` locais de conexão remota. |
| `WPFTweaksUTC` | Relógio de Hardware em UTC | *(Apenas Dev)* Define `RealTimeIsUniversal = 1` para sincronização perfeita de relógio em Dual-Boot com Linux. |
| `WPFToggleDetailedBSoD` | Ativa tela azul detalhada (Verbose BSoD) | Exibe o driver exato da falha para diagnóstico. |
| `WPFToggleTaskbarAlignment` | Centralização da Barra de Tarefas | Alinhamento padrão dos ícones da barra. |
| `WPFToggleLongPaths` | Habilita Caminhos Longos no FileSystem | Evita erros de limite `MAX_PATH` (260 caracteres) em compilações. |
| `WPFToggleShowExt` | Exibe extensões de arquivos conhecidas | Torna visíveis `.bat`, `.ps1`, `.json`, `.uproject`. |
| `WPFToggleHiddenFiles` | Exibe arquivos e pastas ocultas | Essencial para desenvolvedores e criadores inspecionarem `%APPDATA%`. |
| `WPFToggleGameMode` | Força o Windows Game Mode | Garante priorização de recursos do sistema e agendamento de CPU/GPU para jogos. |
| `WPFToggleDarkMode` | Força Modo Escuro no Sistema | Aplica tema escuro no Windows e nos aplicativos compatíveis. |
| `WPFToggleScrollbars` | Barras de Rolagem Sempre Visíveis | Evita barras de rolagem sumindo automaticamente no Explorer e apps. |
| `WPFToggleDisableLockscreen` | Pula Tela de Bloqueio | Vai direto para a digitação de senha/PIN ao inicializar ou despertar. |
| `WPFToggleVerboseLogon` | Mensagens Detalhadas de Boot | *(Apenas Dev)* Exibe status detalhado de serviços carregados no boot e shutdown. |
| `WPFToggleNumLock` | NumLock Ativado no Boot | Inicializa o teclado numérico sempre ativado na inicialização. |
| `WPFToggleBatteryPercentage` | Porcentagem Numérica de Bateria | *(Apenas Notebooks)* Exibe o número percentual de bateria na barra de tarefas. |
| `WPFInstallchrome` | Instalação do Google Chrome | Navegador padrão. |
| `WPFInstall7zip` | Instalação do utilitário 7-Zip | Descompactador de alta performance. |
| `WPFInstallvc2015_64` | Visual C++ 2015-2022 x64 | Runtimes de 64-bits. |
| `WPFInstallvc2015_32` | Visual C++ 2015-2022 x86 (32-bit) | Compatibilidade com plugins e jogos legados. |
| `WPFFeaturewsl` | Habilita WSL *(Apenas Dev)* | Subsistema Linux nativo. |
| `WPFFeatureshyperv` | Habilita Hyper-V *(Apenas Dev)* | Hipervisor para Docker Desktop e VMs. |
| `WPFFeaturesSandbox` | Habilita Windows Sandbox *(Apenas Dev)* | Ambiente descartável para testes de segurança. |
| `WPFFeaturesdotnet` | Habilita .NET Framework 3.5 / 2.0 | Compatibilidade com softwares legados e plugins 3D. |
| `WPFFeatureRegBackup` | Backup Diário do Registro (RegBack) | Reativa rotina periódica automática de backup do Registro descontinuada pela Microsoft. |

---

## 4. Como Executar

### Via Inicializador One-Click (Recomendado)
Dê dois cliques no arquivo `run.bat` na raiz do repositório e selecione a opção desejada de `[1]` a `[5]`.

### Via Terminal
Execute no PowerShell como Administrador dentro da pasta do repositório:
```powershell
.\scripts\apply-dewin.ps1
```
*(Ou passe o parâmetro direto: `-Profile DesktopDev`, `-Profile DesktopGeral`, `-Profile LaptopDev`, `-Profile LaptopGeral`)*.
