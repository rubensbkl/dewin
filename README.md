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

---

## 🎯 Cargas de Trabalho Alvo

* **Jogos e Esports** (Latência 1:1, Game Mode, HAGS, compatibilidade com anti-cheats)
* **Unreal Engine 5** (LongPathsEnabled para shaders, runtimes legados, tolerância a TDR)
* **DaVinci Resolve Studio / Free** (Codecs preservados, TdrDelay, NVENC)
* **Adobe Creative Cloud** (Premiere Pro, After Effects, Photoshop, Adobe Fonts)
* **Desenvolvimento** (WSL2, Docker Desktop, OpenSSH nativo, Git)
* **Uso Diário** (Sem telemetria de consumidor e anúncios)

---

## 🎛️ Perfis Disponíveis

* **`[1] Full (Dev + Criador + Jogos)`**:
  * Inclui WSL2, Hyper-V, Windows Sandbox, Runtimes VC++ All-in-One, Chrome, 7-Zip e tweaks de sistema.
* **`[2] Creator & Gamer (Edição 3D + Vídeo + Jogos)`**:
  * Focado em DaVinci Resolve, Premiere, Blender e jogos. Aplica tweaks de SSD, GPU e runtimes, sem ativar virtualização Linux/Hyper-V.

---

## 📁 Estrutura do Repositório

```
dewin/
├── unattend/
│   └── autounattend.xml    # Instalação autônoma limpa (Camada 1)
├── winutil/
│   ├── dewin-full.json     # Perfil completo (Dev + Criador + Gamer)
│   ├── dewin-creator.json  # Perfil Criador & Gamer (Sem WSL/Hyper-V)
│   ├── dewin.json          # Perfil padrão
│   └── README.md           # Guia de integração WinUtil
├── scripts/
│   └── apply-dewin.ps1     # Script de automação pós-instalação (Camada 2)
├── iniciar.bat             # Inicializador rápido (elevação e execução com 2 cliques)
├── docs/
│   ├── architecture.md     # Arquitetura e fluxo de instalação
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

### Etapa 1: Instalação Limpa via Pendrive
1. Grave a ISO oficial (`Win11_25H2_BrazilianPortuguese_x64_v2.iso`) em um pendrive com o Rufus (particionamento GPT / UEFI).
2. Copie o arquivo [`unattend/autounattend.xml`](unattend/autounattend.xml) para a raiz do pendrive (`D:\autounattend.xml`).
3. Inicialize o computador pelo pendrive:
   * Setup autônomo sem exigência de conta Microsoft (usuário local `Admin`).
   * Bypass preventivo de TPM/RAM aplicado.
   * Bloatware UWP removido e GPU configurada com `TdrDelay = 8s`.
   * Microsoft Store, OpenSSH Client e .NET 3.5 offline preservados.

### Etapa 2: Pós-Instalação
1. Conecte o computador à internet.
2. Dê **dois cliques** no arquivo [`iniciar.bat`](iniciar.bat) na raiz da pasta (ele solicita elevação de Administrador e configura as permissões automaticamente).
   * *Alternativa via terminal*: abra o PowerShell na pasta do projeto e execute:
     ```powershell
     .\scripts\apply-dewin.ps1
     ```
3. Selecione o perfil desejado:
   * `[1]` para **Full** (com WSL2 e Hyper-V).
   * `[2]` para **Creator & Gamer** (sem virtualização).
4. Reinicie o computador após a conclusão.

---

## 📚 Documentação

* [Arquitetura do Sistema](docs/architecture.md)
* [Matriz de Otimizações](docs/optimizations.md)
* [Inventário de Aplicativos](docs/removed-apps.md)
* [Guia de Reversão / Rollback](docs/rollback.md)
* [Integração com WinUtil](winutil/README.md)
* [Guia de Contribuição](CONTRIBUTING.md)
* [Licença MIT](LICENSE)