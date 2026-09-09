import { LightningElement, api } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';

const STAGES = [
    { name: 'Identificada',      short: 'Identificada' },
    { name: 'Qualificada',       short: 'Qualificada' },
    { name: 'Em Elaboração',     short: 'Em Elaboração' },
    { name: 'Aprovação Interna', short: 'Aprovação' },
    { name: 'Proposta Enviada',  short: 'Proposta Enviada' },
    { name: 'Em Negociação',     short: 'Em Negociação' },
    { name: 'Adjudicada',        short: 'Adjudicada' },
    { name: 'Closed Won',        short: 'Closed Won' }
];

const SPECIAL_STAGES = {
    'Closed Lost': 6,
    'Suspensa':    5,
    'Cancelada':   6
};

// Índices das fases que têm ecrã de edição genérico no Flow (revisit Opção A):
// Identificada (0), Qualificada (1), Em Elaboração (2). As fases seguintes são
// transições de estado/aprovação sem campos-chave editáveis, por isso não são revisitáveis.
const EDITABLE_INDEXES = new Set([0, 1, 2]);

export default class ScFlowProgressBar extends LightningElement {
    @api stageName = '';

    // Output para o Flow: stage do step clicado pelo utilizador (revisit de fase anterior).
    // O Flow lê este valor para rotear ao ecrã de edição genérico desse stage.
    @api selectedStageName = '';

    // Quando true, os steps passados ficam clicáveis (revisit). Quando false, comporta-se
    // como o componente display-only original (ecrãs read-only, fecho, erro, etc.).
    @api allowRevisit = false;

    get currentIndex() {
        const idx = STAGES.findIndex(s => s.name === this.stageName);
        if (idx >= 0) return idx;
        // Stages especiais: usa a fase anterior definida acima
        const fallback = SPECIAL_STAGES[this.stageName];
        return fallback !== undefined ? fallback : 0;
    }

    get isSpecialStage() {
        return Object.prototype.hasOwnProperty.call(SPECIAL_STAGES, this.stageName);
    }

    get specialBadgeLabel() {
        return this.stageName;
    }

    // Devolve array de items para o template.
    // A linha de ligação é um elemento separado entre wrappers — cada step tem
    // showLine:true para os primeiros N-1 steps; o template renderiza um div.step-line
    // fora do step-wrapper para manter o flex correcto.
    get stepsWithLines() {
        const result = [];
        STAGES.forEach((stage, i) => {
            const isDone   = i < this.currentIndex;
            const isActive = i === this.currentIndex;
            // Só os steps passados (índice < actual) são clicáveis, só quando o Flow
            // pede revisit (allowRevisit), e só se a fase tem ecrã de edição (Opção A).
            // Step actual e futuros nunca clicáveis.
            const isClickable = this.allowRevisit && isDone
                && !this.isSpecialStage && EDITABLE_INDEXES.has(i);
            let circleClass = isDone   ? 'step-circle step-circle--done'
                            : isActive ? 'step-circle step-circle--active'
                            : 'step-circle step-circle--future';
            if (isClickable) {
                circleClass += ' step-circle--clickable';
            }
            result.push({
                key: `step-${i}`,
                index: i,
                stage: stage.name,
                number: i + 1,
                name: stage.name,
                short: stage.short,
                isDone,
                isActive,
                isFuture: i > this.currentIndex,
                isClickable,
                circleClass,
                ariaLabel: isClickable
                    ? `Voltar à fase ${stage.short} para editar`
                    : stage.short,
                tabindex: isClickable ? '0' : '-1',
                isLine: false
            });
            if (i < STAGES.length - 1) {
                result.push({
                    key: `line-${i}`,
                    isLine: true,
                    lineClass: isDone ? 'step-line step-line--done' : 'step-line step-line--future'
                });
            }
        });
        return result;
    }

    get currentStageLabel() {
        const s = STAGES[this.currentIndex];
        return s ? s.short : this.stageName;
    }

    get phaseLabel() {
        const base = `Fase ${this.currentIndex + 1} de ${STAGES.length} — ${this.currentStageLabel}`;
        return this.isSpecialStage ? `${base} (${this.specialBadgeLabel})` : base;
    }

    get revisitHint() {
        return this.allowRevisit && this.currentIndex > 0 && !this.isSpecialStage;
    }

    handleStepClick(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        // Guard: só aceita clique em step passado, editável e em modo revisit.
        if (!this.allowRevisit || isNaN(idx) || idx >= this.currentIndex
                || this.isSpecialStage || !EDITABLE_INDEXES.has(idx)) {
            return;
        }
        const chosen = STAGES[idx].name;
        this.selectedStageName = chosen;
        // Comunica ao Flow o stage escolhido (o Flow define selectedStageName como output).
        this.dispatchEvent(new FlowAttributeChangeEvent('selectedStageName', chosen));
    }

    handleStepKeydown(event) {
        if (event.key === 'Enter' || event.key === ' ' || event.key === 'Spacebar') {
            event.preventDefault();
            this.handleStepClick(event);
        }
    }
}