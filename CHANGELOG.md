# Changelog

All notable changes to the **DEWIN** project will be documented in this file.

---

## [1.0.0] - 2026-09-19

### Added
- **Camada 1 (Unattended Setup)**:
  - Arquivo `unattend/autounattend.xml` auditado e otimizado para Windows 11 Pro 25H2 x64 (pt-BR).
  - Instalação 100% autônoma sem exigência de conta Microsoft (usuário local `Admin`).
  - Bypass preventivo de TPM, Secure Boot e RAM.
  - Bloqueio de injeção da Asus WPBT (Armoury Crate) na placa-mãe ASUS TUF B550M.
  - Desativação de Fast Startup problemático (`HiberbootEnabled = 0`).
  - Instalação offline do `.NET Framework 3.5` a partir de `sources\sxs`.
  - Habilitação de caminhos longos (`LongPathsEnabled = 1`) para compilações na Unreal Engine 5.
  - Preservação da **Microsoft Store**, **OpenSSH Client**, **Notepad moderno** e **RDP Client**.
  - Expurgados 32 pacotes UWP desnecessários (Copilot, Bing, Clipchamp, News, Teams de consumidor).
- **Camada 2 (Pós-Instalação & WinUtil)**:
  - Script mestre `scripts/apply-dewin.ps1` com criação de ponto de restauração, liberação de SSD, calibração de GPU, ativação de WSL2 e runtimes silenciosos.
  - Perfil calibrado `winutil/dewin.json` para o utilitário CTT WinUtil, excluindo tweaks de risco (como Adobe URL Block List, desativação de IPv6 e perda de fontes/thumbnails).
  - Calibração de `TdrDelay` da NVIDIA RTX 5060 Ti para evitar travamentos de driver no DaVinci Resolve e Unreal Engine.
  - Habilitação automatizada de `Microsoft-Windows-Subsystem-Linux` e `VirtualMachinePlatform`.
- **Documentação Técnica Completa**:
  - `docs/architecture.md`: Diagrama de arquitetura em duas camadas e ciclo de vida.
  - `docs/optimizations.md`: Matriz detalhada de otimizações de kernel, GPU, SSD e mitigação de mitos ("anti-snake oil").
  - `docs/removed-apps.md`: Inventário exaustivo de pacotes removidos e justificativas de preservação.
  - `docs/rollback.md`: Guia passo a passo de restauração completa e pontual.
  - `winutil/README.md`: Manual de importação e uso do perfil WinUtil.
  - `README.md`: Guia de uso direto da criação do pendrive à execução do script pós-instalação.