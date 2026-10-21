# Orientações para os Projetos com IA

Este documento orienta o Claude (e qualquer outra IA) na hospedagem e manutenção dos meus sistemas no servidor. Leia antes de criar, alterar ou publicar qualquer coisa.

## 1. Contexto

Estou hospedando no servidor um conjunto de relatórios e sistemas internos. Cada sistema roda em uma porta própria da faixa 3000-3999. As portas 3001 a 3020 estão livres em todos os servidores. As portas 3000 e 3050 já têm dono definido.

## 2. Mapa de sistemas e portas

| Sistema | Porta | Observação |
| --- | --- | --- |
| Lançamento de movimentações | 3000 | Porta fixa |
| Relatório gerencial | 3001 | |
| Metas | 3002 | |
| Relatório de notas fiscais lançadas | 3003 | |
| Relatório de margens aplicadas | 3004 | |
| Controle de validade | 3050 | Porta fixa |

Portas livres para novos sistemas: 3005 a 3020.

## 3. Regras de hospedagem

1. Cada sistema usa uma porta exclusiva. Nunca reaproveite uma porta já listada acima.
2. Não altere as portas 3000 e 3050 sem eu pedir.
3. Ao criar um novo sistema, use a próxima porta livre (a partir de 3005) e atualize a tabela da seção 2 no mesmo momento.
4. A porta deve ser configurável por variável de ambiente (`PORT`), com o valor da tabela como padrão.
5. Cada sistema fica em sua própria pasta, com seu próprio arquivo de dependências e instruções de execução.
6. Cada sistema deve subir sozinho após reinicialização do servidor (serviço do sistema ou gerenciador de processos).
7. Antes de iniciar um sistema, verifique se a porta já está em uso. Se estiver, pare e me avise em vez de trocar de porta por conta própria.

## 4. Estrutura sugerida por projeto

```
/projetos
  /relatorio-gerencial        (3001)
  /metas                      (3002)
  /notas-fiscais-lancadas     (3003)
  /margens-aplicadas          (3004)
  /controle-validade          (3050)
  /lancamento-movimentacoes   (3000)
```

Cada pasta contém:

- `README.md` com o que o sistema faz, a porta e como iniciar
- `.env.example` com as variáveis necessárias (sem valores reais)
- código-fonte e arquivo de dependências

## 5. Segurança e dados

- Nunca coloque senhas, tokens ou strings de conexão dentro do código. Use arquivo `.env` fora do controle de versão.
- Não envie dados reais (notas fiscais, margens, metas) para serviços externos sem minha autorização.
- Os relatórios de margens e o relatório gerencial contêm informação sensível: o acesso deve ficar restrito à rede interna.
- Não apague dados nem arquivos permanentemente sem confirmação.
- Faça backup antes de qualquer alteração em banco de dados ou na estrutura de um sistema já em uso.

## 6. Como a IA deve trabalhar

- Pergunte antes de decidir quando houver risco de perder dados ou de afetar um sistema em produção.
- Explique o que fez em poucas linhas: o que mudou, onde está e como testar.
- Prefira soluções simples e fáceis de manter. Evite dependências desnecessárias.
- Escreva código e comentários em português quando fizer sentido, e nomes de variáveis de forma clara.
- Quando faltar informação (tecnologia do servidor, banco de dados, usuários), pergunte em vez de supor.

## 7. Checklist de publicação (por sistema)

- [ ] A aplicação escuta na porta correta da tabela
- [ ] A porta está liberada no firewall do servidor
- [ ] O sistema inicia automaticamente após reiniciar o servidor
- [ ] O acesso foi testado a partir de outra máquina da rede
- [ ] As credenciais estão em `.env`, fora do código
- [ ] O `README.md` do sistema está atualizado
- [ ] A tabela da seção 2 reflete a realidade

## 8. Informações a preencher

Complete estes pontos para que a IA não precise adivinhar:

- Sistema operacional do servidor: _______
- Endereço/nome do servidor: _______
- Linguagem/framework dos sistemas: _______
- Banco de dados utilizado: _______
- Quem acessa cada sistema: _______
- Como é feito o backup: _______
