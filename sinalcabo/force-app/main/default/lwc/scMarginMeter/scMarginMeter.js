import { LightningElement, api } from 'lwc';

// Cor do assistente (mesma dos cabecalhos dos ecras do flow).
const COR_NEUTRA = '#007878';
const COR_NEGATIVA = '#E53935';

/**
 * Medidor de margem do ecra G2 do flow SC_Guiar_Pipeline.
 *
 * Mostra a margem que resulta do valor e do custo acabados de introduzir, e mais nada. Nao ha
 * zonas nem limiares aqui: quem decide se a proposta precisa de aprovacao e' a matriz
 * Regra_Aprovacao__c, que varia por comercial e por classificacao, e o ecra de confirmacao a
 * seguir ja mostra o veredicto real. Um limiar escrito no componente contradiria a matriz.
 *
 * Unica leitura de valor: margem negativa fica a vermelho, porque a validacao do ecra a recusa.
 */
export default class ScMarginMeter extends LightningElement {
    @api amount = 0;
    @api cost = 0;

    get marginPct() {
        const a = parseFloat(this.amount) || 0;
        const c = parseFloat(this.cost) || 0;
        return a > 0 ? ((a - c) / a) * 100 : 0;
    }

    get isEmpty() {
        return !this.amount || parseFloat(this.amount) === 0;
    }

    get colorHex() {
        return this.marginPct < 0 ? COR_NEGATIVA : COR_NEUTRA;
    }

    get marginLabel() {
        return `${this.marginPct.toFixed(1)}%`;
    }

    get statusLabel() {
        return this.marginPct < 0 ? 'Margem negativa' : 'Margem estimada';
    }

    get valueStyle() {
        return `color: ${this.colorHex};`;
    }

    get statusStyle() {
        return `color: ${this.colorHex};`;
    }
}