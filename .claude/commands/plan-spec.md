Gere o plano de implementação para o spec `specs/$ARGUMENTS.md`.

**Esta é a fase de PLAN. Não crie, edite ou delete nenhum arquivo do
projeto durante este comando — apenas leia e produza o plano.**

Passos:
1. Leia `specs/$ARGUMENTS.md` por completo.
2. Leia o `CLAUDE.md` para relembrar decisões de arquitetura fechadas e
   convenções do repositório.
3. Se o spec depender de outro spec anterior (verificar seção de
   pré-requisitos), confirme que o spec anterior está marcado como
   concluído no `CLAUDE.md`. Se não estiver, pare e avise — não gere o
   plano.
4. Se houver decisão técnica em aberto que o spec não resolveu
   explicitamente (ex: topologia de rede, dimensionamento de recursos,
   escolha entre alternativas equivalentes), liste essas decisões
   separadamente no início do plano, sob o título "Decisões pendentes",
   e pergunte antes de assumir um valor padrão.
5. Produza `specs/$ARGUMENTS.plan.md` com esta estrutura:
   - **Pré-requisitos verificados**: lista do que já precisa existir
   - **Decisões pendentes** (se houver): perguntas para o usuário, com
     opções e trade-offs de cada uma
   - **Tarefas numeradas**: cada uma com o arquivo exato a criar/editar,
     o comando exato a rodar, e a dependência entre tarefas (ordem)
   - **Riscos identificados**: o que pode dar errado e como mitigar
   - **Comandos de validação básica**: os comandos que o Implement vai
     rodar ao final de cada tarefa (não a validação formal do spec —
     essa fica para `/validate-spec`)
6. Não prossiga para implementação. Aguarde aprovação explícita do plano.
