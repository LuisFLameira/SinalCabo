import { LightningElement, api, track, wire } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import getCriteria    from '@salesforce/apex/SC_G1CriterioSelector.getCriteria';
import getOppScores   from '@salesforce/apex/SC_G1CriterioSelector.getOpportunityScores';

export default class ScG1Scorer extends LightningElement {

    // ── Inputs do Flow ────────────────────────────────────────────────────
    @api recordId;

    // Propriedades legadas — declaradas para compatibilidade com o meta.xml (não usadas)
    @api q01 = '0'; @api q02 = '0'; @api q03 = '0'; @api q04 = '0';
    @api q05 = '0'; @api q06 = '0'; @api q07 = '0'; @api q08 = '0';
    @api q09 = '0'; @api q10 = '0'; @api q11 = '0';

    // ── Outputs ao Flow (declarados @api para FlowAttributeChangeEvent) ──
    @api scoresJson      = '{}';
    @api scoreCalculated = '0';

    // ── Estado interno ────────────────────────────────────────────────────
    @track _localScores  = {};        // scores actuais (pré-populados + interacção user)
    @track _criteriaData = [];        // dados da CMT
    _criteriaLoaded  = false;
    _scoresLoaded    = false;
    _initialFired    = false;
    _fromInput       = false;

    // ── Retoma após BACK ──────────────────────────────────────────────────
    // O Flow devolve o scoresJson que já tinha capturado. Se vier preenchido,
    // pré-popula a partir dele (em vez do registo, que ainda não foi gravado),
    // para não perder a selecção do utilizador ao recuar.
    connectedCallback() {
        if (this.scoresJson && this.scoresJson !== '{}') {
            try {
                const parsed = JSON.parse(this.scoresJson);
                if (parsed && Object.keys(parsed).length > 0) {
                    this._localScores  = { ...parsed };
                    this._fromInput    = true;
                    this._scoresLoaded = true;
                }
            } catch (e) {
                // JSON inválido: ignora e segue o carregamento do registo
            }
        }
    }

    // ── Wire: critérios da CMT ────────────────────────────────────────────
    @wire(getCriteria)
    wiredCriteria({ data, error }) {
        if (data) {
            this._criteriaData = data;
            this._criteriaLoaded = true;
            this._tryFireInitial();
        }
        // error: deixar isLoading=true indefinidamente para não crashar
    }

    // ── Wire: scores actuais da Opportunity ──────────────────────────────
    @wire(getOppScores, { recordId: '$recordId' })
    wiredScores({ data, error }) {
        if (this._fromInput) {
            // já pré-populado a partir do input do Flow (retoma após BACK): não sobrepor com o registo
            this._scoresLoaded = true;
            this._tryFireInitial();
            return;
        }
        if (data) {
            this._localScores = { ...data };
            this._scoresLoaded = true;
            this._tryFireInitial();
        } else if (error) {
            // Opp não encontrada ou sem campos — iniciar com 0s
            this._scoresLoaded = true;
            this._tryFireInitial();
        }
    }

    _tryFireInitial() {
        if (!this._initialFired && this._criteriaLoaded && this._scoresLoaded) {
            this._initialFired = true;
            this._fireOutputs();
        }
    }

    // ── Loading / Empty states ────────────────────────────────────────────
    get isLoading() {
        return !this._criteriaLoaded || !this._scoresLoaded;
    }

    get isEmpty() {
        return !this.isLoading && this._criteriaData.length === 0;
    }

    // ── Score calculado ───────────────────────────────────────────────────
    get score() {
        if (this._criteriaData.length === 0) return 0;
        return this._criteriaData.reduce((acc, c) => {
            const val = parseFloat(this._localScores[c.API_Name__c] || '0') || 0;
            return acc + val * (c.Weight__c || 0);
        }, 0);
    }

    get scoreFormatted() { return this.score.toFixed(2); }
    get isGo()   { return this.score >= 3.0; }
    get isNoGo() { return !this.isGo; }

    // ── Gauge SVG ─────────────────────────────────────────────────────────
    get gaugeColor() {
        if (this.score < 2) return '#E53935';
        if (this.score < 3) return '#FB8C00';
        return '#43A047';
    }

    get gaugeDashArray() {
        const R   = 70;
        const arc = Math.PI * R;
        const pct = Math.min(Math.max(this.score / 5, 0), 1);
        return `${(pct * arc).toFixed(2)} ${arc.toFixed(2)}`;
    }

    // ── Aviso se soma pesos ≠ 100% ────────────────────────────────────────
    get weightWarning() {
        if (this._criteriaData.length === 0) return false;
        const sum = this._criteriaData.reduce((s, c) => s + (c.Weight__c || 0), 0);
        return Math.abs(sum - 1.0) > 0.005;
    }

    // ── Critérios agrupados por categoria ─────────────────────────────────
    get criteria() {
        const catOrder = [];
        const catMap   = {};

        for (const c of this._criteriaData) {
            const cat = c.Category__c || 'Outro';
            if (!catMap[cat]) {
                catOrder.push(cat);
                catMap[cat] = {
                    key:         cat,
                    label:       cat,
                    style:       `background:${c.Bg_Color__c};border-left:4px solid ${c.Border_Color__c};`,
                    headerStyle: `color:${c.Header_Color__c};`,
                    activeColor: c.Border_Color__c,
                    items:       []
                };
            }
            const curVal = this._localScores[c.API_Name__c] || '0';
            const borderColor = catMap[cat].activeColor;
            catMap[cat].items.push({
                prop:   c.API_Name__c,
                label:  c.Label,
                weight: `${Math.round((c.Weight__c || 0) * 100)}%`,
                icon:   c.Icon__c || 'utility:info',
                buttons: ['0','1','2','3','4','5'].map(v => ({
                    value:       v,
                    label:       v,
                    isActive:    curVal === v,
                    btnClass:    curVal === v ? 'score-btn score-btn--active' : 'score-btn',
                    activeStyle: curVal === v ? `background:${borderColor};border-color:${borderColor};color:white;` : ''
                }))
            });
        }
        return catOrder.map(k => catMap[k]);
    }

    // ── Handlers ──────────────────────────────────────────────────────────
    handleScore(event) {
        const field = event.currentTarget.dataset.criterion;
        const val   = event.currentTarget.dataset.value;
        this._localScores = { ...this._localScores, [field]: val };
        this._fireOutputs();
    }

    _fireOutputs() {
        const json = JSON.stringify(this._localScores);
        const sc   = this.score.toFixed(2);
        this.dispatchEvent(new FlowAttributeChangeEvent('scoresJson',      json));
        this.dispatchEvent(new FlowAttributeChangeEvent('scoreCalculated', sc));
    }
}