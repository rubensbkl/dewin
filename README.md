# DEWIN — Windows 11 Workstation

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Base: Windows 11 25H2](https://img.shields.io/badge/Windows%2011-25H2%20Pro-0078D6.svg)](iso/README.md)
[![Platform: AMD & Intel](https://img.shields.io/badge/Architecture-x64-orange.svg)](docs/architecture.md)

Instalação limpa, modular e otimizada do **Windows 11 Pro 25H2 x64 (pt-BR)** baseada exclusivamente na ISO oficial da Microsoft.

Foco em desempenho, baixa latência e redução de processos em segundo plano para criação de conteúdo, modelagem 3D, desenvolvimento e jogos, sem quebrar drivers ou serviços essenciais.

---

## 🖥️ Matriz de Compatibilidade de Hardware

| Componente | Compatibilidade e Suporte |
| :--- | :--- |
| **Processadores AMD** | **Ryzen 3000, 5000, 7000 e 9000** (Zen 2 a Zen 5). Plano de energia balanceado nativo com AMD CPPC para curvas de boost corretas. |
| **Processadores Intel** | **Core 10ª a 15ª Geração**. Suporte ao Intel Thread Director nativo do Windows 11. |
| **Placas de Vídeo NVIDIA** | **GeForce GTX 10xx em diante e RTX (20/30/40/50)**. Calibração de `TdrDelay = 8s` (estabilidade em render) e HAGS ativado. |
| **Placas de Vídeo AMD** | **Radeon RX 5000 em diante**. Suporte a Smart Access Memory (SAM). |
| **Placas-mãe** | **ASUS, MSI, Gigabyte, ASRock**. Bloqueio de injeção de bloatware via firmware WPBT (ex: ASUS Armoury Crate). |
| **Armazenamento** | **SSDs NVMe e SATA**. Recupera ~31 GB ao desativar hibernação e armazenamento reservado. |
| **Notebooks Homologados** | **Acer Nitro V 15** (calibração dGPU/Optimus, NitroSense e hibernação segura) e **ASUS VivoBook 14/15** (preservação de teclas Fn, limite de bateria MyASUS 80% e hibernação segura). Compatíveis com ambos os perfis (Dev ou Geral). |

---

## 🎯 Cargas de Trabalho Alvo

* **Jogos e Esports** (Latência 1:1, Game Mode, HAGS, compatibilidade com anti-cheats)
* **Unreal Engine 5** (LongPathsEnabled para shaders, runtimes legados, tolerância a TDR)
* **DaVinci Resolve Studio / Free** (Codecs preservados, TdrDelay, NVENC)
* **Adobe Creative Cloud** (Premiere Pro, After Effects, Photoshop, Adobe Fonts)
* **Desenvolvimento** (WSL2, Docker Desktop, OpenSSH nativo, Git)
* **Uso Diário** (Sem telemetria de consumidor e anúncios)

---

## 🎛️ Perfis Disponíveis (Matriz 2x2)

A escolha do perfil é orientada pela **sua carga de trabalho** (necessidade de virtualização/Docker vs. economia de recursos), e não pelo modelo do computador. Ambos os notebooks homologados (**Acer Nitro V 15** e **ASUS VivoBook**) e desktops suportam qualquer perfil:

| Hardware | Finalidade Dev / Workstation | Finalidade Geral, Jogos & Produtividade |
| :--- | :--- | :--- |
| **Desktop** | **`[1] Desktop Dev`**: WSL2, Hyper-V, Sandbox, liberação máxima de SSD (sem hibernação). | **`[2] Desktop Geral & Jogos`**: Máxima leveza, FPS e SSD liberado, sem virtualização. |
| **Notebook**<br>*(Nitro V 15, VivoBook, etc.)* | **`[3] Notebook Dev`**: WSL2, Hyper-V, Sandbox, ferramentas Dev, hibernação segura compacta (~3 GB). | **`[4] Notebook Geral & Jogos`**: Máxima autonomia de bateria, leveza, sem virtualização, hibernação segura compacta (~3 GB). |

---

## 📁 Estrutura do Repositório

```
dewin/
├── unattend/
│   └── autounattend.xml    # Instalação autônoma limpa (Camada 1)
├── winutil/
│   ├── dewin-desktop-dev.json    # Desktop Dev & Workstation
│   ├── dewin-desktop-geral.json  # Desktop Geral & Jogos
│   ├── dewin-laptop-dev.json     # Notebook Dev & Workstation (Nitro V 15, VivoBook, etc.)
│   ├── dewin-laptop-geral.json   # Notebook Geral & Produtividade / Jogos (Nitro V 15, VivoBook, etc.)
│   └── README.md                 # Guia de integração WinUtil e inventário
├── scripts/
│   └── apply-dewin.ps1     # Script de automação e Booster do sistema
├── run.bat                 # Inicializador rápido (elevação e execução com 2 cliques)
├── docs/
│   ├── architecture.md     # Arquitetura e fluxos de uso
│   ├── optimizations.md    # Matriz técnica de alterações
│   ├── removed-apps.md     # Inventário de apps removidos e preservados
│   └── rollback.md         # Guia de reversão e restauração
├── iso/
│   └── README.md           # Metadados e hash SHA-256 da ISO oficial
├── CONTRIBUTING.md         # Diretrizes de contribuição
├── LICENSE                 # Licença MIT
├── CHANGELOG.md            # Histórico de alterações
└── README.md               # Este documento
```

---

## 🚀 Como Usar

O DEWIN foi projetado com suporte para dois perfis de uso:

### 🔹 Fluxo A: Instalação Limpa via Pendrive (Setup Novo)
1. Grave a ISO oficial (`Win11_25H2_BrazilianPortuguese_x64_v2.iso`) em um pendrive com o Rufus (particionamento GPT / UEFI).
2. Copie o arquivo [`unattend/autounattend.xml`](unattend/autounattend.xml) para a raiz do pendrive (`D:\autounattend.xml`).
3. Inicialize o computador pelo pendrive:
   * Setup autônomo sem exigência de conta Microsoft (usuário local `Admin`).
   * Bypass preventivo de TPM/RAM aplicado.
   * Bloatware UWP removido e GPU configurada com `TdrDelay = 8s`.
   * Microsoft Store, OpenSSH Client e .NET 3.5 offline preservados.
4. Após o primeiro boot, execute o `run.bat` para aplicar os pacotes e runtimes finais.

### 🔹 Fluxo B: Booster em Máquina Viva (Sem Formatar)
*Se você já possui o Windows instalado e em produção, e quer apenas dar um boost máximo sem formatar:*
1. Baixe ou clone a pasta do projeto.
2. Dê **dois cliques** no arquivo [`run.bat`](run.bat) na raiz do repositório (ou execute `.\scripts\apply-dewin.ps1` no PowerShell como Administrador).
3. O script aplicará automaticamente:
   * **Calibração de GPU**: `TdrDelay = 8s`, `TdrDdiDelay = 8s` e HAGS para estabilidade em DaVinci Resolve, Unreal Engine e jogos.
   * **Debloat Cirúrgico**: Remoção de 28 pacotes nativos de bloatware e telemetria.
   * **Tweaks do WinUtil**: Hibernação, Armazenamento Reservado, menu clássico, extensões de arquivos, serviços e runtimes.
4. Selecione o perfil desejado (`[1]` a `[4]` de acordo com seu dispositivo e necessidade de trabalho) e reinicie o computador ao finalizar.

---

## 📚 Documentação

* [Arquitetura do Sistema](docs/architecture.md)
* [Matriz de Otimizações](docs/optimizations.md)
* [Inventário de Aplicativos](docs/removed-apps.md)
* [Guia de Reversão / Rollback](docs/rollback.md)
* [Integração com WinUtil](winutil/README.md)
* [Guia de Contribuição](CONTRIBUTING.md)
* [Licença MIT](LICENSE)