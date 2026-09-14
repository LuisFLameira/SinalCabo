import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import iniciar from '@salesforce/apex/SC_PniCarregamentoController.iniciar';
import processar from '@salesforce/apex/SC_PniCarregamentoController.processar';
import concluir from '@salesforce/apex/SC_PniCarregamentoController.concluir';

/**
 * Carregamento do ficheiro do PNI.
 *
 * O ficheiro não é enviado inteiro. Tem 10,4 MB e a memória de uma transacção no
 * servidor são 6 MB, por isso é lido aqui no navegador e mandado aos pedaços, um de
 * cada vez. O servidor devolve a cauda, que é o que ficou depois do último registo
 * completo, e essa cauda vai à frente do pedaço seguinte: assim nunca se parte uma
 * linha ao meio, nem quando ela tem aspas com mudanças de linha lá dentro.
 *
 * O percurso tem cinco momentos: escolher, verificar, rever, importar e o resultado.
 * A verificação é uma simulação que lê tudo e não grava nada, para a pessoa ver o
 * impacto antes de confirmar.
 */
const PEDACO = 500000;
const PASSO_ESCOLHER = 'escolher';
const PASSO_VERIFICAR = 'verificar';
const PASSO_REVER = 'rever';
const PASSO_IMPORTAR = 'importar';
const PASSO_FIM = 'fim';

export default class ScPniCarregamento
    extends NavigationMixin(LightningElement) {
    @track passo = PASSO_ESCOLHER;
    @track erro;
    @track aviso;
    @track ensaio;
    @track resultado;
    @track lidas = 0;
    @track total = 0;

    ficheiro;
    nomeFicheiro;
    codificacao = 'utf-8';
    loteEnsaioId;
    loteRealId;

    get opcoesCodificacao() {
        return [
            { label: 'UTF-8', value: 'utf-8' },
            { label: 'Windows-1252, Europa Ocidental', value: 'windows-1252' }
        ];
    }

    get naEscolha() {
        return this.passo === PASSO_ESCOLHER;
    }
    get aTrabalhar() {
        return this.passo === PASSO_VERIFICAR || this.passo === PASSO_IMPORTAR;
    }
    get naRevisao() {
        return this.passo === PASSO_REVER;
    }
    get noFim() {
        return this.passo === PASSO_FIM;
    }
    get semFicheiro() {
        return !this.ficheiro;
    }

    get cabecalho() {
        if (this.passo === PASSO_VERIFICAR) {
            return '● A verificar o ficheiro';
        }
        if (this.passo === PASSO_IMPORTAR) {
            return '● A importar';
        }
        if (this.passo === PASSO_FIM) {
            return this.resultado && this.resultado.rejeitados > 0
                ? '⚠ Importação concluída com linhas de fora'
                : '✓ Importação concluída';
        }
        if (this.passo === PASSO_REVER) {
            return '● Por confirmar';
        }
        return '● Por carregar';
    }

    get oQueEstaAFazer() {
        return this.passo === PASSO_VERIFICAR
            ? 'A ler o ficheiro. Nenhuma ordem é alterada nesta passagem.'
            : 'A gravar as ordens.';
    }

    get progresso() {
        if (!this.total) {
            return 0;
        }
        return Math.min(100, Math.round((this.lidas * 100) / this.total));
    }

    get textoProgresso() {
        return `${this.lidas} de ${this.total} linhas lidas. `
            + 'Pode sair desta página: a importação não pára.';
    }

    /** Acima de cinco por cento de linhas de fora, convém olhar antes de confirmar. */
    get demasiadasDeFora() {
        return this.ensaio && this.ensaio.lidos > 0
            && this.ensaio.rejeitados / this.ensaio.lidos > 0.05;
    }

    get resumoFora() {
        if (!this.ensaio) {
            return '';
        }
        return `${this.ensaio.rejeitados} de ${this.ensaio.lidos} linhas ficam de fora. `
            + 'Confirme que o ficheiro é o certo antes de avançar.';
    }

    // ------------------------------------------------------------------
    // Escolher
    // ------------------------------------------------------------------

    trocarCodificacao(evento) {
        this.codificacao = evento.detail.value;
    }

    escolherFicheiro(evento) {
        this.erro = undefined;
        const ficheiros = evento.target.files;
        if (!ficheiros || !ficheiros.length) {
            this.ficheiro = undefined;
            return;
        }
        this.ficheiro = ficheiros[0];
        this.nomeFicheiro = this.ficheiro.name;
    }

    async verificar() {
        if (!this.ficheiro) {
            return;
        }
        this.erro = undefined;
        this.passo = PASSO_VERIFICAR;
        try {
            const texto = await this.lerTexto(this.ficheiro);
            this.total = this.contarLinhas(texto);
            const inicio = await iniciar({
                nomeFicheiro: this.nomeFicheiro, simulacao: true
            });
            this.loteEnsaioId = inicio.loteId;
            this.ensaio = await this.enviarAosPedacos(texto, inicio.loteId, true);
            await concluir({ loteId: inicio.loteId });
            this.passo = PASSO_REVER;
        } catch (e) {
            this.falhar(e);
        }
    }

    // ------------------------------------------------------------------
    // Importar
    // ------------------------------------------------------------------

    async importar() {
        this.erro = undefined;
        this.passo = PASSO_IMPORTAR;
        this.lidas = 0;
        try {
            const texto = await this.lerTexto(this.ficheiro);
            const inicio = await iniciar({
                nomeFicheiro: this.nomeFicheiro, simulacao: false
            });
            this.loteRealId = inicio.loteId;
            this.resultado = await this.enviarAosPedacos(texto, inicio.loteId, false);
            await concluir({ loteId: inicio.loteId });
            this.passo = PASSO_FIM;
        } catch (e) {
            this.falhar(e);
        }
    }

    voltar() {
        this.passo = PASSO_ESCOLHER;
        this.ensaio = undefined;
        this.lidas = 0;
    }

    recomecar() {
        this.passo = PASSO_ESCOLHER;
        this.ficheiro = undefined;
        this.nomeFicheiro = undefined;
        this.ensaio = undefined;
        this.resultado = undefined;
        this.lidas = 0;
        this.total = 0;
    }

    /** Leva a pessoa ao lote, que e onde vivem os contadores e as linhas de fora. */
    abrirLote() {
        const id = this.loteRealId || this.loteEnsaioId;
        if (!id) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: { recordId: id, objectApiName: 'Lote_Integracao__c',
                          actionName: 'view' }
        });
    }

    // ------------------------------------------------------------------
    // Motor
    // ------------------------------------------------------------------

    /**
     * Manda o texto aos pedaços, em série. Em série de propósito: a cauda de um
     * pedaço tem de chegar antes de o seguinte ser lido, e o servidor vai somando no
     * lote, que não aguenta duas escritas ao mesmo tempo.
     */
    async enviarAosPedacos(texto, loteId, simulacao) {
        const soma = {
            lidos: 0, criados: 0, actualizados: 0, inalterados: 0,
            rejeitados: 0, forasDeJanela: 0, divergentes: 0
        };
        let colunas = null;
        let cauda = '';
        let numero = 1;
        let posicao = 0;

        while (posicao < texto.length) {
            const fim = Math.min(posicao + PEDACO, texto.length);
            const ultimo = fim >= texto.length;
            const pedaco = cauda + texto.substring(posicao, fim);
            posicao = fim;

            const p = await processar({
                loteId,
                pedaco,
                colunas,
                numeroInicial: numero,
                ultimo,
                simulacao
            });
            if (p.erro) {
                throw new Error(p.erro);
            }
            colunas = p.colunas;
            cauda = p.cauda || '';
            numero += p.lidos;
            this.lidas = numero - 1;

            soma.lidos += p.lidos;
            soma.criados += p.criados;
            soma.actualizados += p.actualizados;
            soma.inalterados += p.inalterados;
            soma.rejeitados += p.rejeitados;
            soma.forasDeJanela += p.forasDeJanela;
            soma.divergentes += p.divergentes;
        }
        return soma;
    }

    lerTexto(ficheiro) {
        return new Promise((resolver, rejeitar) => {
            const leitor = new FileReader();
            leitor.onload = () => resolver(leitor.result);
            leitor.onerror = () => rejeitar(new Error(
                'Não foi possível ler o ficheiro. Verifique que não está aberto '
                + 'noutro programa e tente outra vez.'));
            leitor.readAsText(ficheiro, this.codificacao);
        });
    }

    contarLinhas(texto) {
        let n = 0;
        for (let i = 0; i < texto.length; i++) {
            if (texto[i] === '\n') {
                n++;
            }
        }
        return n;
    }

    falhar(e) {
        const corpo = e && e.body ? e.body.message : undefined;
        this.erro = corpo || (e && e.message)
            || 'A importação parou e nada mais foi gravado. '
               + 'Tente outra vez; se voltar a parar, avise o administrador.';
        this.passo = this.ensaio ? PASSO_REVER : PASSO_ESCOLHER;
    }
}