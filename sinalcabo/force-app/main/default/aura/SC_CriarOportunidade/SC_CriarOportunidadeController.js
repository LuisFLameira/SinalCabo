({
    doInit : function(component) {
        var flow = component.find("flow");
        // lança o flow guiado sem recordId (o utilizador escolhe a Conta no flow)
        flow.startFlow("SC_Criacao_Rapida");
    },
    handleStatus : function(component, event) {
        var status = event.getParam("status");
        if (status === "FINISHED" || status === "FINISHED_SCREEN") {
            var nav = component.find("navService");
            // Ler o Id da opp criada a partir dos output variables do flow.
            // Navegar para o registo (standard__recordPage) evita o problema de
            // list views em mobile (standard__objectPage list nao resolve em iOS/Android).
            var oppId = null;
            var outputVars = event.getParam("outputVariables");
            if (outputVars) {
                for (var i = 0; i < outputVars.length; i++) {
                    if (outputVars[i].name === "outputOppId") {
                        oppId = outputVars[i].value;
                        break;
                    }
                }
            }
            if (oppId) {
                nav.navigate({
                    type: "standard__recordPage",
                    attributes: { recordId: oppId, objectApiName: "Opportunity", actionName: "view" }
                });
            } else {
                // Fallback defensivo (nao esperado): sem Id, vai para a home da app.
                nav.navigate({
                    type: "standard__namedPage",
                    attributes: { pageName: "home" }
                });
            }
        }
    }
})