# Inventário de Aplicativos: Removidos e Preservados

Este documento registra os aplicativos e recursos modificados durante a instalação do **DEWIN**, demonstrando o critério rigoroso para não quebrar dependências do sistema.

---

## 1. Aplicativos UWP / AppX Removidos

Estes pacotes são desprovisionados para todos os usuários durante a fase *Specialize* do setup do Windows:

| Pacote AppX | Nome Amigável | Motivo da Remoção |
| :--- | :--- | :--- |
| `Microsoft.Microsoft3DViewer` | Visualizador 3D | Obsoleto; substituído por softwares dedicados (Blender, Unreal). |
| `Microsoft.BingSearch` | Bing Search App | Telemetria de busca web não solicitada. |
| `Clipchamp.Clipchamp` | Clipchamp Video Editor | Editor web desnecessário; a máquina utiliza **DaVinci Resolve** e **Premiere Pro**. |
| `Microsoft.Copilot` | Microsoft Copilot | Módulo de telemetria generativa e IA em segundo plano. |
| `Microsoft.Windows.Ai.Copilot.Provider` | Copilot Provider | Provedor de dados de IA em segundo plano. |
| `Microsoft.549981C3F5F10` | Cortana | Descontinuada pela Microsoft. |
| `Microsoft.Windows.DevHome` | Dev Home | Ferramenta acessória pesada da Microsoft com alto consumo de memória. |
| `MicrosoftCorporationII.MicrosoftFamily` | Microsoft Family Safety | Controle parental desnecessário para estação pessoal. |
| `Microsoft.WindowsFeedbackHub` | Hub de Feedback | Coleta de telemetria e diagnóstico interativo. |
| `Microsoft.Edge.GameAssist` | Edge Game Assist | Widget promocional de jogos do Edge. |
| `Microsoft.GetHelp` | Obter Ajuda | Assistente de suporte básico. |
| `Microsoft.Getstarted` | Dicas / Começar | Tutoriais de introdução ao Windows. |
| `microsoft.windowscommunicationsapps` | Email e Calendário legados | Clientes de email legados substituíveis pelo Outlook Web ou client de preferência. |
| `Microsoft.WindowsMaps` | Mapas do Windows | Inútil em computador desktop fixo. |
| `Microsoft.MixedReality.Portal` | Portal de Realidade Misturada | Plataforma WMR descontinuada pela Microsoft. |
| `Microsoft.BingNews` | Notícias | Feed de notícias promocionais. |
| `Microsoft.MicrosoftOfficeHub` | Hub do Office 365 | Anúncios e atalhos para assinatura da Microsoft 365. |
| `Microsoft.Office.OneNote` | OneNote UWP | Versão simplificada em UWP. |
| `Microsoft.OutlookForWindows` | Novo Outlook (PWA) | Aplicativo empacotado baseado em web view. |
| `Microsoft.People` | Pessoas (Contatos) | Integração legada de contatos. |
| `Microsoft.PowerAutomateDesktop` | Power Automate Desktop | Ferramenta de automação empresarial em segundo plano. |
| `MicrosoftCorporationII.QuickAssist` | Assistência Rápida | Suporte remoto não utilizado em estação pessoal. |
| `Microsoft.SkypeApp` | Skype | Mensageiro legado com serviços em background. |
| `Microsoft.MicrosoftSolitaireCollection` | Coleção de Paciência | Jogo promocional com anúncios da Microsoft. |
| `Microsoft.MicrosoftStickyNotes` | Notas Autoadesivas | Utilidade opcional com serviços em nuvem. |
| `MicrosoftTeams` / `MSTeams` | Microsoft Teams Pessoal | Versão de consumidor do Teams que inicializa com o Windows. |
| `Microsoft.Todos` | Microsoft To Do | Gerenciador de tarefas da nuvem. |
| `Microsoft.Wallet` | Carteira do Windows | Pagamentos integrados da Microsoft. |
| `Microsoft.BingWeather` | Clima | Previsão do tempo com telemetria e feeds. |
| `Microsoft.YourPhone` | Vincular ao Celular | Sincronização constante com smartphone em segundo plano. |
| `Microsoft.ZuneMusic` | Media Player moderno | Player básico substituível por players dedicados (VLC, etc.). |
| `Microsoft.OneDrive` | Microsoft OneDrive | Desinstalado completamente; desativa interceptação das pastas de usuário (`Desktop`, `Documents`, `Pictures`) e serviço `OneSyncSvc`. |

---

## 2. Recursos Opcionais e Capabilities Removidos

| Recurso / Capability | Motivo da Remoção |
| :--- | :--- |
| `Recall` | Módulo de captura contínua de tela por inteligência artificial (IA). |
| `Browser.InternetExplorer` | Compatibilidade legada do motor IE11 obsoleta. |
| `MathRecognizer` | Reconhecimento de escrita manual matemática. |
| `OneCoreUAP.OneSync` | Sincronização de contas legadas de email/calendário. |
| `Language.Handwriting` | Suporte a reconhecimento de escrita à mão (inútil sem caneta/tablet). |
| `Language.Speech` / `TextToSpeech` | Recursos de ditado e leitura em voz alta. |
| `App.StepsRecorder` | Gravador de Passos legado descontinuado. |
| `Hello.Face.*` | Reconhecimento facial por câmera IR (hardware desktop comum não possui câmera compatível). |
| `Microsoft.Windows.WordPad` | Editor WordPad descontinuado no Windows 11 24H2/25H2. |

---

## 3. Componentes CRÍTICOS Preservados (O que NÃO foi removido)

A integridade do DEWIN depende da presença intocada destes componentes:

| Componente | Por que foi PRESERVADO |
| :--- | :--- |
| **Microsoft Store** (`Microsoft.WindowsStore`) | **Crítico**: Necessária para o **NVIDIA Control Panel** da RTX 5060 Ti, codecs de aceleração por hardware (HEVC, AV1) no DaVinci/Premiere e gerenciador de pacotes Winget. |
| **OpenSSH Client** (`OpenSSH.Client`) | **Crítico**: Necessário para Git, chaves SSH nativas, VS Code Remote e administração de servidores no terminal. |
| **Bloco de Notas Moderno** (`Microsoft.WindowsNotepad`) | Mantido com abas e sem hacks de registro legados que causam erros de associação de arquivos. |
| **RDP Client** (`Microsoft-RemoteDesktopConnection`) | Ferramenta leve (`mstsc.exe`) vital para desenvolvedores conectarem em máquinas remotas e VMs. |
| **Microsoft Defender (Antivírus)** | Mantido ativo para proteção contínua de arquivos, compilações e downloads. |
| **SmartScreen** | Mantido ativo contra malwares e instaladores desconhecidos da internet. |
| **Edge WebView2 Runtime** | Preservado obrigatoriamente. O inicializador da **Epic Games / Unreal Engine** e o instalador da **Adobe Creative Cloud** exigem o WebView2 para telas de login. |
| **Xbox Services & Game Bar** | Preservados para total compatibilidade com jogos do Xbox App / Game Pass e controles Bluetooth/USB. |
