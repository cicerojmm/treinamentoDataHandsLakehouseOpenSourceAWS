Implemente o spec `specs/$ARGUMENTS.md` seguindo o plano aprovado.

**Esta é a fase de IMPLEMENT (Build). Requer que `specs/$ARGUMENTS.plan.md`
já exista.**

Passos:
1. Verifique se `specs/$ARGUMENTS.plan.md` existe. Se não existir, pare e
   instrua a rodar `/plan-spec $ARGUMENTS` primeiro — não gere um plano
   improvisado aqui.
2. Leia o plano por completo antes de tocar em qualquer arquivo.
3. Execute as tarefas na ordem definida no plano, uma por vez.
4. Após cada tarefa, rode o comando de validação básica correspondente
   (definido no plano) antes de seguir para a próxima. Se falhar,
   diagnostique a causa antes de tentar corrigir — não pule para a
   próxima tarefa com uma tarefa anterior quebrada.
5. Não faça alterações fora do escopo do plano. Se perceber que algo
   fora do escopo é necessário, pare e reporte — não improvise.
6. Ao final de todas as tarefas, NÃO marque o spec como concluído. Isso
   só acontece depois de `/validate-spec $ARGUMENTS` passar. Reporte que
   a implementação terminou e está pronta para validação.
