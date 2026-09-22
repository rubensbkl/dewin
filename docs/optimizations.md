# Matriz de Otimizações do Projeto DEWIN

Este documento detalha cada modificação implementada no projeto **DEWIN**, as chaves de registro ou comandos associados, o impacto real no hardware e as justificativas para cada software alvo.

---

## 1. Otimizações de Sistema e Kernel

| Otimização | Mecanismo / Chave de Registro | Benefício Real | Workload / Hardware |
| :--- | :--- | :--- | :--- |
| **Desativação de Fast Startup** | `HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Power\HiberbootEnabled = 0` | Elimina a hibernação híbrida do kernel ao desligar. Garante inicialização limpa sem acúmulo de bugs de drivers NVIDIA/USB. | Estabilidade geral e drivers NVIDIA |
| **Desativação de Hibernação** | `powercfg.exe /hibernate off` | Libera de 16 a 24 GB de espaço em SSD NVMe (tamanho correspondente à RAM) e reduz ciclos de gravação no SSD. | Desktops (Armazenamento) |
| **Hibernação Segura Compacta** | `powercfg /h /type reduced` | Mantém `hiberfil.sys` reduzido (~3 GB) para segurança em bateria crítica (< 3%) e suspensão segura na mochila. | Notebooks (Acer Nitro, ASUS VivoBook, etc.) |
| **Preservação de Teclas Fn & Bateria ASUS** | Serviços `AsusSysCap` e `ASUSOptimization` ativos | Assegura funcionamento de teclas Fn (brilho, volume, atalhos) e limite de carga a 80% do MyASUS. | ASUS VivoBook |
| **Preservação Térmica Acer Nitro** | Serviços Acer / Nitro ativos | Garante funcionamento pleno do NitroSense (curvas de ventoinha e modos térmicos). | Acer Nitro V 15 |
| **Desativação de Armazenamento Reservado** | `DISM.exe /Online /Set-ReservedStorageState /State:Disabled` | Devolve ~7 GB de espaço em disco que ficava retido exclusivamente para atualizações. | SSD NVMe (Armazenamento) |
| **Habilitação de Caminhos Longos** | `HKLM\SYSTEM\CurrentControlSet\Control\FileSystem\LongPathsEnabled = 1` | Remove a barreira de 260 caracteres do `MAX_PATH`. Impede falhas de compilação em árvores profundas. | **Unreal Engine 5**, C++, Git, npm |
| **Bloqueio Global WPBT** | `HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\DisableWpbtExecution = 1` | Impede que a BIOS de qualquer fabricante (ASUS, Lenovo, HP, Gigabyte) injete instaladores e bloatware no Windows. | Segurança e Desempenho |
| **Bloqueio Logi Download Assistant & Razer** | `icacls deny write` nativo no `apply-dewin.ps1` | Impede a injeção dos instaladores de periféricos (Logitech e Razer) ao plugar mouses/teclados. | Periféricos e Mouses |
| **Desativação de Carimbo de Último Acesso** | `fsutil behavior set disablelastaccess 1` | Elimina escritas desnecessárias de metadados no SSD a cada leitura de arquivo e acelera pastas com milhares de arquivos. | **SSD NVMe (Vida Útil & Leitura)** |
| **Desativação de Device Metadata Promocional** | `HKLM\Software\Microsoft\Windows\CurrentVersion\Device Metadata\PreventDeviceMetadataFromNetwork = 1` | Impede o download automático de bloatware de fabricantes de monitores/mouses pela Windows Store. | Periféricos e Monitores |
| **Permissão de Scripts PowerShell** | `Set-ExecutionPolicy -Scope LocalMachine -ExecutionPolicy RemoteSigned -Force` | Permite rodar scripts locais do DEWIN e ferramentas de automação sem erros de política restritiva. | **Desenvolvimento** |
| **Tela Azul Detalhada (Verbose BSoD)** | `HKLM\SYSTEM\CurrentControlSet\Control\CrashControl\DisplayParameters = 1` | Exibe o nome exato do módulo `.sys` causador de eventuais falhas em vez do emoji resumido. | Debug na Unreal e tuning de hardware |
| **Backup Diário do Registro (RegBack)** | `EnablePeriodicBackup = 1` + Tarefa `AutoRegBackup` | Reativa a rotina periódica automática de backup das hives do Registro descontinuada pela Microsoft. | Estabilidade e Disaster Recovery |
| **Relógio em UTC (Dual-Boot)** | `HKLM\SYSTEM\CurrentControlSet\Control\TimeZoneInformation\RealTimeIsUniversal = 1` | Sincroniza o relógio do hardware em UTC para computadores com Windows e Linux em Dual-Boot. | **Desenvolvimento / Dual-Boot** |
| **Calibração de Memória SvcHost** | `HKLM\SYSTEM\CurrentControlSet\Control\SvcHostSplitThresholdInKB = [RAM_KB]` | Agrupa serviços do sistema em menos processos `svchost.exe`, reduzindo overhead de alocação de memória. | Desempenho e RAM |

---

## 2. Otimizações Gráficas, Latência e Jogos

| Otimização | Mecanismo / Chave de Registro | Benefício Real | Workload / Hardware |
| :--- | :--- | :--- | :--- |
| **Desativação de Network Throttling** | `Multimedia\SystemProfile\NetworkThrottlingIndex = 0xffffffff` | Remove o limitador de processamento de rede não-multimídia do Windows. Reduz jitter e perda de pacotes. | **Jogos Multiplayer e Rede** |
| **Prioridade Total de CPU em Foco** | `Multimedia\SystemProfile\SystemResponsiveness = 0` | Garante 100% dos ciclos de processamento de CPU para a aplicação em primeiro plano (0% reservado para tarefas secundárias). | **Jogos, Unreal Engine 5, DaVinci** |
| **Desativação Completa do GameDVR** | `GameConfigStore\GameDVR_Enabled = 0` + GPO `AllowGameDVR = 0` | Elimina o processo em background de gravação contínua da Microsoft, causador de micro-travamentos (stutters). | **Jogos e FPS Estável** |
| **Aumento de TdrDelay da GPU** | `HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\TdrDelay = 8` | Aumenta o tempo limite de resposta da GPU de 2s para 8s antes que o Windows resete o driver de vídeo. | **DaVinci Resolve**, **Unreal Engine 5**, **After Effects** |
| **Aumento de TdrDdiDelay** | `HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\TdrDdiDelay = 8` | Garante tolerância similar para chamadas de interface de driver de dispositivo do DirectX. | **DaVinci Resolve**, **Unreal Engine 5** |
| **Hardware-Accelerated GPU Scheduling (HAGS)** | `HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\HwSchMode = 2` | Permite à GPU gerenciar sua própria memória de vídeo diretamente, reduzindo latência do DWM e habilitando DLSS 3. | **NVIDIA RTX**, Jogos, Premiere |
| **Windows Game Mode Forçado** | `HKCU\Software\Microsoft\GameBar\AllowAutoGameMode = 1` | Garante priorização de recursos do sistema e agendamento ótimo de CPU/GPU para jogos. | **Jogos e Esports** |
| **Desativação de Aceleração de Mouse (1:1)** | `HKCU\Control Panel\Mouse\MouseSpeed = 0` | Proporciona rastreamento de cursor 1:1 estritamente linear sem aceleração errática. | **Jogos (FPS)** e precisão em Viewports |
| **Desativação de Teclas de Aderência (Sticky Keys)** | `Accessibility\StickyKeys\Flags = 506` | Elimina a caixa de diálogo de interrupção ao pressionar `Shift` repetidamente em jogos. | **Jogos e Produtividade** |
| **Multiplane Overlay (MPO) Mantido** | Padrão nativo do driver NVIDIA | Permite composição de camadas de vídeo com latência ultra-baixa e suporte total a HDR sem stuttering. | **NVIDIA RTX**, Monitores HDR |

---

## 3. Otimizações de Interface e Produtividade

| Otimização | Mecanismo / Chave de Registro | Benefício Real |
| :--- | :--- | :--- |
| **Ocultar Caixa/Botão de Pesquisa da Barra** | `HKCU\Software\Microsoft\Windows\CurrentVersion\Search\SearchboxTaskbarMode = 0` | Elimina a poluição visual na barra de tarefas; a busca permanece acessível abrindo o Iniciar e digitando. |
| **Ocultar Botão de Multitarefa (Task View)** | `HKCU\...\Explorer\Advanced\ShowTaskViewButton = 0` | Remove o ícone de Visão de Tarefas da barra; o atalho de teclado `Win + Tab` permanece totalmente funcional. |
| **Alinhamento da Barra ao Centro** | `HKCU\...\Explorer\Advanced\TaskbarAl = 1` | Mantém o visual moderno, balanceado e padrão centralizado do Windows 11. |
| **Eliminar Atraso de Menus (Instantâneo)** | `HKCU\Control Panel\Desktop\MenuShowDelay = 0` | Remove a espera artificial padrão de 400ms do Windows para exibição de submenus suspensos. |
| **Menu de Contexto Clássico** | `HKCU\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32` | Acesso instantâneo a todas as opções de ferramentas de desenvolvedor (Git, 7-Zip, Editores) sem submenus lentos. |
| **Abertura em "Este Computador" & Sem Galeria** | `LaunchTo = 1` + CLSID `{f874310e...}` e `{e88865ea...}` | Abre o Explorer diretamente nos discos locais e remove atalhos visuais pesados (Início e Galeria). |
| **Finalizar Tarefa na Barra de Tarefas** | `HKCU\...\TaskbarDeveloperSettings\TaskbarEndTask = 1` | Permite encerrar processos travados com botão direito na barra de tarefas sem abrir o Gerenciador de Tarefas. |
| **Exibir Extensões e Ocultos** | `HideFileExt = 0` e `Hidden = 1` no Explorer | Essencial para programadores e criadores de conteúdo inspecionarem arquivos `.json`, `.ini`, `.uproject`, `.bat`. |
| **Barras de Rolagem Sempre Visíveis** | `DynamicScrollbars = 0` | Evita que barras de rolagem sumam sozinhas em editores de código, logs e janelas do Explorer. |
| **Pular Tela de Bloqueio Estática** | `NoLockScreen = 1` | Vai direto para a digitação de senha/PIN ao ligar ou despertar o computador. |
| **Eliminar Tela "Vamos Concluir a Configuração" (SCOOBE)** | `ScoobeSystemSettingEnabled = 0` | Nunca mais exibe tela cheia após atualizações do Windows pedindo para assinar o Office 365 ou configurar PIN. |
| **Modo Escuro Nativo no Sistema** | `AppsUseLightTheme = 0` e `SystemUsesLightTheme = 0` | Interface escura padronizada para menor fadiga visual em longas sessões de trabalho. |
| **NumLock Ativado no Boot** | `InitialKeyboardIndicators = 2` | Garante teclado numérico ativo ao iniciar sem precisar pressionar a tecla NumLock. |
| **Porcentagem de Bateria na Barra** | `IsBatteryPercentageEnabled = 1` *(Apenas Notebooks)* | Exibe o número percentual de carga direto na bandeja do sistema no Windows 11. |
| **Avisos de RDP Não Assinado Desativados** | `RedirectionWarningDialogVersion = 1` *(Apenas Dev)* | Elimina caixas de diálogo repetitivas de confirmação ao abrir arquivos `.rdp` locais de conexão. |
| **Mensagens Detalhadas de Boot (Verbose)** | `VerboseStatus = 1` *(Apenas Dev)* | Exibe status detalhado de serviços sendo iniciados/parados para diagnóstico de inicialização lenta. |
| **Desativar Descoberta Automática de Pastas** | `AllFolders\Shell\FolderType = "NotSpecified"` | Pastas pesadas com centenas de vídeos ou assets 3D abrem instantaneamente sem que o Explorer engasgue. |

---

## 4. Otimizações de Privacidade e Ruído de Fundo

| Otimização | Mecanismo / Chave de Registro | Benefício Real |
| :--- | :--- | :--- |
| **Desativação de Tarefas Agendadas de Telemetria** | `Compatibility Appraiser`, `ProgramDataUpdater`, `Consolidator`, `UsbCeip` | Elimina picos repentinos de 100% de uso de disco e CPU quando o computador fica ocioso por 5 minutos. |
| **Remoção Completa do OneDrive** | `OneDriveSetup.exe /uninstall` + Limpeza de pastas | Desinstalação completa do OneDrive, liberando recursos e impedindo a captura indesejada de pastas de usuário. |
| **Debloat do Microsoft Edge** | Políticas GPO em `HKLM\SOFTWARE\Policies\Microsoft\Edge` | Desativa telemetria em segundo plano, popups promocionais, cupons e assistentes do Edge (mantém o WebView2). |
| **Desativação de IA, Copilot e Recall** | `SettingsPageVisibility = hide:aicomponents` + GPO Notepad | Desativa atalhos de IA, serviço `WSAIFabricSvc` e recurso opcional `Recall`. |
| **Bloqueio de Consumer Features** | `Policies\Microsoft\Windows\CloudContent\DisableWindowsConsumerFeatures = 1` | Impede que o Windows instale jogos patrocinados silenciosamente após o primeiro boot. |
| **Desativação de ContentDeliveryManager e Anúncios** | Zeradas chaves de `ContentDeliveryManager` | Elimina sugestões, promoções, anúncios no app Configurações e no menu Iniciar. |
| **Desativação de Busca Web do Bing no Iniciar** | `Policies\Microsoft\Windows\Explorer\DisableSearchBoxSuggestions = 1` | A pesquisa no menu Iniciar torna-se 100% local, instantânea e sem vazamento de consultas digitadas para o Bing. |
| **Desativação de Widgets (News and Interests)** | `Policies\Microsoft\Dsh\AllowNewsAndInterests = 0` + Remoção AppX | Elimina o consumo de memória RAM do processo `Widgets.exe` e feeds de notícias no canto da tela. |
| **Desativação de Otimização de Entrega P2P** | `Policies\Microsoft\Windows\DeliveryOptimization\DODownloadMode = 0` | Evita que o Windows envie atualizações para terceiros na internet usando sua conexão. |

---

## 5. Mitos e Otimizações Falsas Evitadas (Anti-Snake Oil)

O projeto DEWIN rejeita explicitamente as seguintes práticas nocivas:

1. **Plano de Energia "Ultimate Performance"**:
   * *Por que NÃO usar*: Em processadores modernos AMD Zen 3 (Ryzen 5 5600X), travar o processador em 100% de frequência mínima aquece o chip em idle e prejudica o teto térmico para o **Precision Boost 2 (PB2)**, diminuindo a capacidade de atingir clocks de 4.65 GHz+ em single-thread. O plano Equilibrado (*Balanced*) nativo é termicamente superior e entrega o mesmo frame time em jogos.
2. **Desativação do Arquivo de Paginação (Pagefile)**:
   * *Por que NÃO desativar*: Compiladores C++ da Unreal Engine e caches de nós do DaVinci Resolve demandam grande alocação de memória virtual (*Commit Charge*). Sem pagefile, mesmo com 32 GB de RAM física, o sistema sofre travamentos catastróficos por *Out of Memory*.
3. **Desativação do Microsoft Defender**:
   * *Por que NÃO desativar*: Em uma estação de trabalho que baixa pacotes do GitHub, assets de lojas 3D e plugins de áudio/vídeo, a desativação do Defender não compensa o ganho negligenciável de performance.
4. **Desativação de IPv6 e Teredo**:
   * *Por que NÃO desativar*: Teredo e IPv6 são obrigatórios para a pilha de rede do Xbox Live, diversos jogos multiplayer com NAT traversal e provedores de internet brasileiros modernos com Dual Stack.
