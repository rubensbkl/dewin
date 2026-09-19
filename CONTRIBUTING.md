# Diretrizes de Contribuição

Instruções para propor melhorias, novos tweaks e correções para o **DEWIN**.

---

## Princípios do Projeto

1. **Eficiência Comprovada**: Apenas modificações com ganho real de desempenho, estabilidade ou espaço em disco. Rejeitamos práticas como desativar arquivo de paginação, forçar clocks estáticos ou desligar IPv6.
2. **Segurança Básica Preservada**: O Microsoft Defender, SmartScreen e atualizações de segurança não devem ser desativados.
3. **Compatibilidade**: Qualquer alteração deve ser testada contra Unreal Engine, DaVinci Resolve, Adobe Creative Cloud, WSL2 e jogos modernos.
4. **Base Oficial**: Uso exclusivo de imagens ISO oficiais da Microsoft.
5. **Reversibilidade**: Toda alteração no sistema deve ter procedimento de rollback documentado em [docs/rollback.md](docs/rollback.md).

---

## Como Contribuir

### Relatando Problemas
Abra uma **Issue** informando:
* Hardware (CPU, GPU, Placa-mãe, RAM).
* Versão da ISO do Windows 11 utilizada.
* Comportamento observado e logs de erro.

### Enviando Pull Requests (PR)
1. Crie um Fork do repositório.
2. Crie uma branch para sua alteração (`git checkout -b feature/minha-melhoria`).
3. Mantenha os scripts PowerShell válidos sintaticamente e documentados.
4. Atualize a documentação correspondente na pasta `docs/`.
5. Envie o PR com a justificativa técnica da mudança.

---

## Licença

Ao contribuir com o projeto DEWIN, suas contribuições serão disponibilizadas sob os termos da [Licença MIT](LICENSE).
