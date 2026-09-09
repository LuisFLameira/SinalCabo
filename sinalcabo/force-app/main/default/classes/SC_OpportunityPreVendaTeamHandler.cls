/**
 * SC_OpportunityPreVendaTeamHandler
 * -------------------------------------------------------------------------
 * Mantem o membro da Opportunity Team com papel "Pre-Venda" sincronizado com
 * o campo Opportunity.Pre_Venda_Lider__c (lookup a User).
 *
 * A Opportunity tem OWD Privado, por isso a entrada na equipa e' o que abre o
 * acesso. O membro e' criado com OpportunityAccessLevel = 'Edit'.
 *
 * Porque Apex e nao Flow: o nivel de acesso (Edit) de um OpportunityTeamMember
 * so e' aplicado de forma fiavel ao OpportunityShare subjacente quando o DML
 * corre em contexto Apex (manual-share capable). Em Flow record-triggered o
 * OpportunityAccessLevel e' frequentemente rebaixado para o minimo calculado.
 *
 * Regra de reconciliacao: o papel "Pre-Venda" e' o marcador do slot
 * auto-gerido. Em cada alteracao do campo, reconcilia-se esse slot para
 * reflectir o valor actual do campo.
 *
 * Edge cases tratados:
 *  - Campo limpo            -> remove o membro Pre-Venda.
 *  - Campo muda de A para B -> remove A, poe B.
 *  - Pre_Venda = OwnerId    -> NAO adiciona (owner ja tem acesso implicito;
 *                              insert daria FIELD_INTEGRITY_EXCEPTION).
 *  - User ja na equipa com outro papel -> NAO cria duplicado; faz update do
 *    registo existente para papel Pre-Venda e acesso >= Edit (sem downgrade
 *    se ja tiver 'All'). Um user so pode estar uma vez na Opportunity Team.
 *
 * Bulkificado: zero SOQL/DML em loops. Uma query de membros, DML em coleccoes.
 */
public with sharing class SC_OpportunityPreVendaTeamHandler {

    @TestVisible private static final String ROLE_PRE_VENDA = 'Pré-Venda';
    @TestVisible private static final String ACCESS_EDIT    = 'Edit';

    /**
     * Ponto de entrada do trigger (after insert / after update).
     * @param newOpps  Trigger.new
     * @param oldMap   Trigger.oldMap (null no insert)
     */
    public static void reconcile(List<Opportunity> newOpps, Map<Id, Opportunity> oldMap) {

        // 1. Identificar as opps cujo Pre_Venda_Lider__c foi definido ou alterado.
        Map<Id, Opportunity> oppsToProcess = new Map<Id, Opportunity>();
        for (Opportunity opp : newOpps) {
            Id oldVal = (oldMap == null) ? null : oldMap.get(opp.Id).Pre_Venda_Lider__c;
            if (opp.Pre_Venda_Lider__c != oldVal) {
                oppsToProcess.put(opp.Id, opp);
            }
        }
        if (oppsToProcess.isEmpty()) {
            return;
        }

        // 2. Carregar os membros de equipa existentes dessas opps (uma so query).
        Map<Id, List<OpportunityTeamMember>> membersByOpp = new Map<Id, List<OpportunityTeamMember>>();
        for (OpportunityTeamMember otm : [
                SELECT Id, OpportunityId, UserId, TeamMemberRole, OpportunityAccessLevel
                FROM OpportunityTeamMember
                WHERE OpportunityId IN :oppsToProcess.keySet()
        ]) {
            if (!membersByOpp.containsKey(otm.OpportunityId)) {
                membersByOpp.put(otm.OpportunityId, new List<OpportunityTeamMember>());
            }
            membersByOpp.get(otm.OpportunityId).add(otm);
        }

        // 3. Calcular as accoes (insert / update / delete) por opp.
        List<OpportunityTeamMember> toInsert = new List<OpportunityTeamMember>();
        List<OpportunityTeamMember> toUpdate = new List<OpportunityTeamMember>();
        Map<Id, OpportunityTeamMember> toDeleteById = new Map<Id, OpportunityTeamMember>();

        for (Opportunity opp : oppsToProcess.values()) {
            Id desiredUser = opp.Pre_Venda_Lider__c;
            Id ownerId     = opp.OwnerId;

            List<OpportunityTeamMember> existing =
                membersByOpp.containsKey(opp.Id) ? membersByOpp.get(opp.Id) : new List<OpportunityTeamMember>();

            // Localizar o membro Pre-Venda actual e indexar membros por user.
            OpportunityTeamMember currentPreVenda = null;
            Map<Id, OpportunityTeamMember> byUser = new Map<Id, OpportunityTeamMember>();
            for (OpportunityTeamMember m : existing) {
                byUser.put(m.UserId, m);
                if (m.TeamMemberRole == ROLE_PRE_VENDA) {
                    // Defensivo: se houver mais que um, mantem o primeiro como "actual"
                    // e marca os restantes para apagar (estado inconsistente).
                    if (currentPreVenda == null) {
                        currentPreVenda = m;
                    } else {
                        toDeleteById.put(m.Id, m);
                    }
                }
            }

            // CASO A: campo limpo OU pre-venda == owner -> nao deve existir membro Pre-Venda.
            if (desiredUser == null || desiredUser == ownerId) {
                if (currentPreVenda != null) {
                    toDeleteById.put(currentPreVenda.Id, currentPreVenda);
                }
                continue;
            }

            // CASO B: o membro Pre-Venda actual ja' e' o user desejado -> garantir acesso Edit.
            if (currentPreVenda != null && currentPreVenda.UserId == desiredUser) {
                if (needsAccessUpgrade(currentPreVenda.OpportunityAccessLevel)) {
                    currentPreVenda.OpportunityAccessLevel = ACCESS_EDIT;
                    toUpdate.add(currentPreVenda);
                }
                continue;
            }

            // CASO C: existe um membro Pre-Venda mas de outro user -> apagar (sera' substituido).
            if (currentPreVenda != null && currentPreVenda.UserId != desiredUser) {
                toDeleteById.put(currentPreVenda.Id, currentPreVenda);
            }

            // O user desejado ja' esta' na equipa com outro papel? -> update, nao duplicar.
            OpportunityTeamMember existingForUser = byUser.get(desiredUser);
            if (existingForUser != null && !toDeleteById.containsKey(existingForUser.Id)) {
                existingForUser.TeamMemberRole = ROLE_PRE_VENDA;
                if (needsAccessUpgrade(existingForUser.OpportunityAccessLevel)) {
                    existingForUser.OpportunityAccessLevel = ACCESS_EDIT;
                }
                toUpdate.add(existingForUser);
                continue;
            }

            // CASO D: inserir novo membro Pre-Venda com acesso Edit.
            toInsert.add(new OpportunityTeamMember(
                OpportunityId          = opp.Id,
                UserId                 = desiredUser,
                TeamMemberRole         = ROLE_PRE_VENDA,
                OpportunityAccessLevel = ACCESS_EDIT
            ));
        }

        // 4. DML em coleccoes (fora de qualquer loop).
        if (!toDeleteById.isEmpty()) {
            delete toDeleteById.values();
        }
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
        if (!toInsert.isEmpty()) {
            insert toInsert;
        }
    }

    /**
     * 'Edit' e 'All' sao suficientes; 'None'/'Read'/null precisam de upgrade.
     * Nunca faz downgrade de 'All'.
     */
    private static Boolean needsAccessUpgrade(String currentAccess) {
        return currentAccess != ACCESS_EDIT && currentAccess != 'All';
    }
}