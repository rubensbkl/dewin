# Arquitetura do Projeto DEWIN

O projeto **DEWIN** é um ecossistema modular e estruturado para entregar o máximo em desempenho, baixa latência, estabilidade de render e limpeza de processos no **Windows 11 Pro 25H2 x64 (pt-BR)**.

---

## 1. Princípios Arquiteturais

1. **ISO 100% Oficial**: Nunca utilizar ISOs modificadas de terceiros (Tiny11, ReviOS, AtlasOS, Ghost Spectre). Modificações externas inserem binários opacos e quebram recursos de segurança e estabilidade.
2. **Modelo Híbrido de Dois Fluxos de Usuário**:
   * **Fluxo A (Instalação Limpa via Pendrive)**: Instalação autônoma via `unattend/autounattend.xml` que entrega o sistema já limpo desde o Windows PE, sem conta Microsoft e com tweaks de GPU/Ke    * **Fluxo B (Booster em Máquina Viva / Sem Formatar)**: Para computadores em produção onde o usuário não pode formatar, o `scripts/apply-dewin.ps1` atua como um *Booster autossuficiente e 100% autônomo*, aplicando nativamente a calibração de GPU, o debloat cirúrgico dos 28 apps, os tweaks de interface (incluindo remoção dos botões de pesquisa e multitarefa), telemetria, kernel, DISM e softwares essenciais sem dependência externa em tempo de execução.
3. **Não-Regressão Funcional**: Nenhuma otimização sacrifica a compatibilidade com ferramentas de produção (Unreal Engine 5, DaVinci Resolve, Adobe Creative Cloud, Docker, WSL2).
4. **Reprodutibilidade Baseada em Código**: Todas as configurações residem em arquivos versionados (`.xml`, `.ps1`, `.json`, `.md`).

---

## 2. Diagrama de Fluxo dos Dois Perfis de Usuário

```mermaid
flowchart TD
    subgraph Flow_A ["Fluxo A: Instalação Limpa (Do Zero)"]
        ISO["ISO Oficial Windows 11"]
        XML["unattend/autounattend.xml"]
        USB["Pendrive de Instalação"]
        ISO --> USB
        XML --> USB
        USB -->|Boot UEFI| WinPE["Windows PE & Setup"]
        WinPE --> Specialize["Specialize: Bypass TPM, GPU TdrDelay, WPBT, LongPaths"]
        Specialize --> OOBE["OOBE Silencioso (Conta Local Admin)"]
        OOBE --> DesktopA["Área de Trabalho Limpa"]
    end

    subgraph Flow_B ["Fluxo B: Booster em Máquina Viva (Sem Formatar)"]
        ExistingPC["PC Existente com Bloatware / Windows em Uso"]
    end

    subgraph Execution ["Execução Unificada: run.bat / apply-dewin.ps1 (Motor Nativo)"]
        DesktopA --> RunBat["run.bat / apply-dewin.ps1"]
        ExistingPC --> RunBat
        
        RunBat --> CoreTweaks["Etapa 1: Calibração GPU (TdrDelay=8s), HAGS, Bateria/Hibernação Inteligente"]
        RunBat --> Debloat["Etapa 2: Debloat Cirúrgico (28 apps UWP nativos)"]
        RunBat --> NativeTweaks["Etapa 3: Motor Nativo DEWIN (Zero Dependência Externa)"]
    end

    subgraph Dewin_Native ["Tweaks Aplicados Nativamente pelo DEWIN"]
        NativeTweaks --> D1["Oculta Botões de Pesquisa e Multitarefa na Barra"]
        NativeTweaks --> D2["Menu de Contexto Clássico, TaskbarEndTask & Alinhamento à Esquerda"]
        NativeTweaks --> D3["Desativa Telemetria, DiagTrack, Windows AI/Copilot & Edge Bloat"]
        NativeTweaks --> D4["Hibernação Inteligente (Desktop: Off / Notebook: Reduced ~3GB)"]
        NativeTweaks --> D5["SvcHostSplitThreshold, Dual-Boot UTC, BSoD Detalhado & LongPaths"]
        NativeTweaks --> D6["Desativa Armazenamento Reservado (~7GB) & Limpeza DISM"]
        NativeTweaks --> D7["Runtimes VC++ (x86/x64), 7-Zip, Chrome & .NET 3.5"]
        NativeTweaks --> D8["Virtualização Modular (WSL2 + Hyper-V + Sandbox - Perfil Dev)"]
    end

    subgraph Ready ["Estação Pronta para Cargas Reais"]
        D1 & D2 & D3 & D4 & D5 & D6 & D7 & D8 --> FinalState["Ambiente Estável, Limpo e Otimizado"]
        FinalState --> Workload1["Unreal Engine 5"]
        FinalState --> Workload2["DaVinci Resolve"]
        FinalState --> Workload3["Adobe Creative Cloud"]
        FinalState --> Workload4["Gaming & Esports"]
    end
```

---

## 3. Divisão de Responsabilidades

| Responsabilidade | Componente Responsável | Fluxo A (Limpo) | Fluxo B (Booster) |
| :--- | :--- | :---: | :---: |
| Bypass de TPM / Secure Boot / RAM | `autounattend.xml` | ✅ (Windows PE) | N/A (Já instalado) |
| Criação da conta local `Admin` sem rede | `autounattend.xml` | ✅ (OOBE) | N/A (Conta existente) |
| Calibração de GPU (`TdrDelay = 8s`, `HAGS`) | `autounattend.xml` + `apply-dewin.ps1` | ✅ | ✅ |
| Bloqueio de injeção WPBT (Asus Armoury Crate) | `autounattend.xml` + `apply-dewin.ps1` | ✅ | ✅ |
| Habilitação de Caminhos Longos (`LongPathsEnabled`) | `autounattend.xml` + `apply-dewin.ps1` | ✅ | ✅ |
| Busca 100% Local (Sem Bing no Iniciar) | `autounattend.xml` + `apply-dewin.ps1` | ✅ | ✅ |
| Ocultar Botões de Pesquisa e Multitarefa | `apply-dewin.ps1` (Nativo) | ✅ (Pós-logon) | ✅ |
| Debloat Cirúrgico (28 apps UWP nativos) | `autounattend.xml` + `apply-dewin.ps1` | ✅ (Pré-logon) | ✅ (Pós-logon) |
| Menu de Contexto Clássico do Windows 10 | `apply-dewin.ps1` (Nativo) + `autounattend.xml` | ✅ | ✅ |
| Exibir Extensões de Arquivo e Pastas Ocultas | `apply-dewin.ps1` (Nativo) + `autounattend.xml` | ✅ | ✅ |
| Desativação de Armazenamento Reservado | `apply-dewin.ps1` (Nativo) | ✅ | ✅ |
| Hibernação Inteligente (Desktop Off / Notebook Reduced) | `apply-dewin.ps1` (Nativo) | ✅ | ✅ |
| Instalação de Runtimes (VC++ 2015-2022, .NET 3.5) | `apply-dewin.ps1` (Nativo / Winget) | ✅ | ✅ |
| Virtualização Modular (WSL2, Hyper-V, Sandbox) | `apply-dewin.ps1` (Nativo - Perfil Dev) | ✅ | ✅ |

---

## 4. Diretrizes para Hardwares Específicos

### CPU: AMD Ryzen 5 5600X (6c/12t - Zen 3)
* **Gerenciamento de Energia**: O Windows 11 gerencia o Precision Boost 2 (PB2) e os núcleos preferenciais (*Preferred Cores*) através do **AMD CPPC** nativo. Planos de energia agressivos ("Ultimate Performance") que travam os núcleos em 100% aumentam o consumo elétrico e diminuem a capacidade da CPU de atingir as frequências máximas de single-core boost. O DEWIN mantém o plano equilibrado nativo otimizado.

### GPU: NVIDIA GeForce RTX 5060 Ti
* **Hardware-Accelerated GPU Scheduling (HAGS)**: Mantido ativo (`HwSchMode = 2`). Essencial para redução de overhead no pipeline de renderização, suporte a Frame Generation (DLSS 3) e encoders NVENC modernos.
* **TdrDelay**: Ajustado para 8 segundos. Evita que o Windows reinicie o driver da placa de vídeo durante compilação intensa de shaders na Unreal Engine ou nós de Fusion/Color no DaVinci Resolve.

### Placa-mãe: ASUS TUF GAMING B550M-PLUS (Desktop)
* **Bloqueio WPBT**: Desativa a injeção automática de firmware do instalador do Asus Armoury Crate (`DisableWpbtExecution = 1`), impedindo serviços desnecessários da Asus em background.
* **Rede Realtek 2.5GbE**: Preservada para máxima vazão em transferências locais e builds.

### Notebooks Homologados: Acer Nitro V 15 & ASUS VivoBook 14/15
Ambos os notebooks foram homologados no DEWIN e **suportam integralmente tanto o perfil Dev quanto o perfil Geral**, conforme a finalidade desejada pelo usuário:

* **Acer Nitro V 15 (Gaming & Workstation Móvel)**:
  * **Gráficos Híbridos & HAGS**: HAGS ativo (`HwSchMode = 2`) para suporte a DLSS 3 e baixa latência. Gerenciamento NVIDIA Optimus / Advanced Optimus preservado para desligar a GPU dedicada quando o notebook opera em bateria.
  * **TdrDelay & Estabilidade**: Tolerância de TDR expandida (`TdrDelay = 8s`, `TdrDdiDelay = 8s`) para renderização pesada e estabilidade gráfica.
  * **Controle Térmico Acer**: Preservação dos serviços e canais do **NitroSense** e **Acer Care Center** para alternância de curvas de ventoinha (Quiet / Default / Performance).
  * **Hibernação Segura**: Hibernação compacta (`powercfg /h /type reduced`, ~3 GB) para proteção contra perda de dados em bateria crítica (< 3%) e sono seguro na mochila (Modern Standby S0ix).
  * *No Perfil Dev*: Habilita WSL2, Hyper-V e aceleração CUDA/dGPU no subsistema Linux.
  * *No Perfil Geral*: Foco máximo em jogos e multitarefa leve, sem alocação de memória RAM para hipervisores em background.

* **ASUS VivoBook 14/15 (Ultrabook Portátil)**:
  * **Teclas de Atalho Fn & Hardware**: Preservados os serviços do **ASUS System Control Interface** (`AsusSysCap`, `ASUSOptimization`), garantindo funcionamento pleno das teclas Fn (brilho de tela, volume, mudo de microfone e touchpad).
  * **Proteção de Bateria (MyASUS Battery Health Charging)**: Suporte preservado para limitação de carga a 80%, aumentando a longevidade da bateria.
  * **Otimização de Vídeo Integrado (iGPU)**: Suporte balanceado para gráficos Intel Iris Xe / AMD Radeon com exibição da porcentagem de bateria na barra.
  * **Hibernação Segura**: Hibernação compacta (`powercfg /h /type reduced`) para proteção contra desligamento súbito em bateria crítica (< 3%).
  * *No Perfil Dev*: Permite desenvolvimento portátil leve com WSL2, Docker e VS Code.
  * *No Perfil Geral*: Máxima autonomia de bateria longe da tomada e temperaturas amenas em repouso.
