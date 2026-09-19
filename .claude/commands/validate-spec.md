Valide a implementação do spec `specs/$ARGUMENTS.md`.

**Esta é a fase de VALIDATE. Deve rodar em um subagent com contexto
limpo — não reaproveite o raciocínio da sessão de implementação.**

Passos:
1. Use a ferramenta de subagent (Task tool, tipo `general-purpose`) para
   criar um revisor independente. Passe para ele apenas:
   - O conteúdo da seção "Critério de Aceite" de `specs/$ARGUMENTS.md`
   - O diff das mudanças feitas (via `git diff` desde o início da
     implementação deste spec)
   Não passe o histórico de conversa da implementação — o revisor deve
   avaliar o resultado por si só, sem viés do raciocínio que o produziu.
2. O subagent deve, para cada item do critério de aceite:
   - Rodar o comando de verificação exato indicado no spec
   - Reportar PASSOU / FALHOU com a saída do comando como evidência
   - Se FALHOU, apontar a causa provável sem tentar corrigir
3. Colete o relatório do subagent e apresente um resumo:
   - Quantos critérios passaram / falharam
   - Para cada falha, o que precisa ser corrigido antes de reexecutar
     `/implement-spec`
4. Se **todos** os critérios passaram:
   - Atualize a seção "Status atual" do `CLAUDE.md`, marcando este spec
     como concluído (Specify + Plan + Implement + Validate)
   - Sugira qual é o próximo spec na ordem de dependência
5. Se algum critério falhou, **não** atualize o `CLAUDE.md` — o spec
   permanece em aberto até nova validação passar.
