--------------------------
-- Montagem do Ambiente --
--------------------------
-- Criando um banco de dados (configura��es padr�o)
CREATE DATABASE [BD_Revisao]

USE BD_Revisao;

-- Criando e Alimentando a Tabela de Teste
CREATE TABLE TabelaDeTeste (
   id     int identity(1,1),
   campoA varchar(20), 
   campoB int,
   campoC datetime,
   campoD decimal(18,8)
) -- DROP TABLE TabelaDeTeste

-- Alimentando a Tabela de Teste
declare @i int
set @i = 1
while (@i <= 2000000) -- Inserindo 2 milh�es de registros 
   begin
		insert into TabelaDeTeste values ('teste: '+ convert(varchar, @i*3), @i*5,getdate(), RAND())
		set @i = @i +1
   end

-- Verificando a tabela de teste
SELECT * FROM TabelaDeTeste

-----------------------------------------------------

-- Criando e Alimentando a Tabela de Rela��o
CREATE TABLE TabelaDeRelacao (
   id     int identity(1,3),
   campoA varchar(20),
) -- DROP TABLE TabelaDeRelacao

-- Alimentando a Tabela de Relacao
declare @j int
set @j = 1
while (@j <= 300000) -- Inserindo 300 mil registros 
   begin
		insert into TabelaDeRelacao values ('Relacao: '+ convert(varchar, @j*2))
		set @j = @j +1
   end

-- verificando a tabela de rela��o
SELECT * FROM TabelaDeRelacao

---------------------------
-- EXECUTAR SQL PROFILER --
---------------------------

-- relacionando as 2 tabelas criadas
SELECT A.campoA
     , R.campoA
	 , A.campoD
  FROM TabelaDeTeste   A
  JOIN TabelaDeRelacao R ON R.id = A.id
-- Tempo de execu��o: 

-- FECHAR E SALVAR O PROFILER

-------------------- 
-- EXECUTAR O DTA --
--------------------
-- - VERIFICAR INDICA��O DE INDICES

-------------------------------------
-- RESTORE / CONSIST�NCIA / BACKUP --
-------------------------------------
-- Restore BD: CorruptDB1.bak

-- https://pessoalex.wordpress.com/2012/01/14/analise-de-um-banco-de-dados-corrompido/ 

CREATE DATABASE [CorruptDB1] ON
( FILENAME = N'C:\temp\SQL\CorruptDB1.mdf' ),
( FILENAME = N'C:\temp\SQL\CorruptDB1_log.ldf' )
FOR ATTACH;
GO

USE CorruptDB1;
-- Paginas corrompidas
SELECT * FROM msdb..Suspect_pages

-- DBCC CHECKDB para ver qual o estado do nosso banco
-- Utilizei as op��es ALL_ERRORMSGS e NO_INFOMSGS para exibir como resultado somente mensagens de erro e ignorar mensagens informativas.
DBCC CHECKDB(CorruptDB1) WITH ALL_ERRORMSGS, NO_INFOMSGS

-- O comando CHECKDB possui duas op��es chamadas REPAIR_ALLOW_DATA_LOSS e REPAIR_REBUILD. 
-- A primeira op��o �tenta� reparar o problema de corrup��o e pode ocasionar perda de dados. 
-- J� a segunda op��o �tenta� executar reparos que n�o possibilitem perda de dados. 
-- Como n�o queremos perder nenhum dado da base, vamos executar a segunda op��o primeiro. 
-- Vou alterar o acesso do banco de dados para SINGLE_USER e vou executar estas op��es.

ALTER DATABASE CorruptDB1 SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
GO

DBCC CHECKDB(CorruptDB1, REPAIR_REBUILD) WITH ALL_ERRORMSGS, NO_INFOMSGS
-- Nada resolvido. Ainda tivemos o erro 8939. 

-- Vamos for�ar a barra e tentar o reparo com poss�vel perda de dados.
DBCC CHECKDB(CorruptDB1, REPAIR_ALLOW_DATA_LOSS) WITH ALL_ERRORMSGS, NO_INFOMSGS
-- Novamente, nada feito. Pelo n�vel de corrup��o do banco de dados, o comando DBCC CHECKDB n�o consegue reparar este problema.
 
-- Vamos ter que fazer uma an�lise um pouco mais profunda e por a m�o na massa para resolver o problema.
-- Em linhas gerais, ele nos informa que foi realizada uma valida��o numa determinada p�gina, e esta valida��o falhou por uma 
-- corrup��o no cabe�alho (Header) da p�gina. Interessante n�o?!

-- Analisando a mensagem completa de erro que nos foi dada, podemos observar que ela nos informa qual � a p�gina que est� com 
-- problema: ��page (1:7). Test (IS_OFF (BUF_IOERR, pBUF->bstat)) failed. ��. Fica a dica: LEIA TODA A MENSAGEM DE ERRO!!! 
-- Achei que isto deveria ficar em destaque pois � muito comum ver as pessoas sem saber o que fazer e a mensagem de erro te d� 
-- dicas valiosas sobre o que aconteceu. Nem sempre � assim, mas na maioria das vezes � v�lido. Vamos dar uma olhada nesta p�gina:

DBCC TRACEON(3604)
GO
DBCC PAGE('CorruptDB1', 1, 7, 3)

-- Page 0 � File Header
-- Page 1 � PFS Page Free Space
-- Page 2 � GAM Global Allocation Map
-- Page 3 � SGAM Shared Global Allocation Map
-- Page 4 e Page 5 � n�o s�o utilizadas
-- Page 6 � DCM Differential Changed Map
-- Page 7 � BCM Bulk Changed Map

-- Isto nos leva � conclus�o de que a p�gina que temos corrompida neste banco de dados � a p�gina BCM, Bulk Changed Map. 
-- � uma das p�ginas de controle de aloca��o de dados do SQL Server.
-- �timo! Agora sabemos o que fazer. Podemos ent�o fazer o restore desta p�gina e tudo resolvido. Vamos tentar.

USE MASTER;
GO
RESTORE DATABASE CorruptDB1
   PAGE = '1:7'
FROM DISK = 'C:\temp\SQL\CorruptDB1.bak'
WITH RECOVERY
-- Vamos utilizar o comando RESTORE para restaurar somente a nossa p�gina corrompida. O resultado que temos �:

/* Msg 3111, Level 16, State 1, Line 2
   Page (1:7) is a control page which cannot be restored in isolation. To repair this page, the entire file must be restored.
   Msg 3013, Level 16, State 1, Line 2
   RESTORE DATABASE is terminating abnormally. */

-- O SQL Server n�o nos permite restaurar isoladamente p�ginas de controle� 
-- E nos informa que para resolu��o do problema temos de restaurar o arquivo completo.

-- Solu��o para o problema e evitar perda de dados. Fa�a um backup de log (Tail Log Backups) e aplica um restore do banco de dados 
-- e depois aplique os logs na sequ�ncia, se houver, e por �ltimo aplique o �ltimo backup de log gerado (tail log).

BACKUP LOG CorruptDB1 TO DISK = 'C:\TEMP\SQL\CorruptDB1_LOG2.bak' WITH STATS = 10

USE master
-- FULL
RESTORE DATABASE CorruptDB1 FROM DISK = 'C:\Temp\SQL\CorruptDB1.bak'
WITH REPLACE
,	 NORECOVERY -- Deixa aberto para recuperar um proximo backup
,	 STATS=10

RESTORE LOG CorruptDB1 FROM  DISK = 'C:\TEMP\SQL\CorruptDB1_LOG1.bak' WITH NORECOVERY
RESTORE LOG CorruptDB1 FROM  DISK = 'C:\TEMP\SQL\CorruptDB1_LOG2.bak' WITH RECOVERY

-- Depois de seguir estes passos, execute novamente o comando DBCC CHECKDB para ter certeza de que seu problema foi resolvido.

-- Paginas corrompidas
SELECT * FROM msdb..Suspect_pages

-- DBCC CHECKDB para ver qual o estado do nosso banco
-- Utilizei as op��es ALL_ERRORMSGS e NO_INFOMSGS para exibir como resultado somente mensagens de erro e ignorar mensagens informativas.
DBCC CHECKDB(CorruptDB1) WITH ALL_ERRORMSGS, NO_INFOMSGS

-- Voltar a Multi-User
ALTER DATABASE CorruptDB1 SET MULTI_USER WITH ROLLBACK IMMEDIATE;