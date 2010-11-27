(function() {
    YAHOO.namespace('Dicty');
    var Dom = YAHOO.util.Dom;

    YAHOO.Dicty.Curation = function() {
//        var logger = new YAHOO.widget.LogReader();
    };

    YAHOO.Dicty.Curation.prototype.init = function() {
        this.geneIDEl = Dom.get('gene-id');
        this.referenceIDEl = Dom.get('reference-id');
        this.curationReferenceButtonEl = 'curation-reference';
        this.curationGeneButtonEl = 'curation-gene';
        this.idTypeCheckboxes = Dom.getElementsByClassName('reference-id-type', 'input');

        // hepl panel used mostly for warnings and error messages
        this.helpPanel = new YAHOO.widget.Panel("helpPanel", {
            width: "500px",
            modal: true,
            fixedcenter: true,
            zIndex: 3,
            visible: false
        });
        this.helpPanel.setBody('');
        this.helpPanel.render(document.body);
        
        // simle dialog used when user confirmation is needed, as of now for confirming pubmed create action
        this.createPubmedDialog = new YAHOO.widget.SimpleDialog("dlg", { 
            width: "30em", 
            effect:{
                effect: YAHOO.widget.ContainerEffect.FADE,
                duration: 0.25
            }, 
            fixedcenter: true,
            modal: true,
            visible: false,
            draggable: false
        });
        
        var handleYes = function() {
            YAHOO.util.Connect.asyncRequest('POST', '/curation/reference/pubmed/' + this.pubmed_id,
            {
                success: function(){
                    location.replace('/curation/reference/pubmed/' + this.pubmed_id);
                },
                failure: function(){},
                scope: this
            });
//            this.hide();
        };
        var myButtons = [
            { text: "Yes", handler: handleYes },
            { text: "Cancel", handler: function(){ this.hide(); }, isDefault:true}
        ];
        
        this.createPubmedDialog.setHeader("Warning!");
        this.createPubmedDialog.setBody("provided PubMed ID was not found in database, do you want to create new reference?");
        this.createPubmedDialog.cfg.setProperty("icon", YAHOO.widget.SimpleDialog.ICON_WARN);
        this.createPubmedDialog.cfg.queueProperty("buttons", myButtons);
        this.createPubmedDialog.render(document.body);

        this.curationGeneButton = new YAHOO.widget.Button({
            container: this.curationGeneButtonEl,
            label: 'Curate',
            type: 'button',
            id: 'curation-gene-button',
            onclick: {
                fn: function() {
                    var valid = this.validateInput(this.geneIDEl.value);
                    if (valid) { 
                        this.curateGene(this.geneIDEl.value); 
                    }
                },
                scope: this
            }
        });

        this.curationReferenceButton = new YAHOO.widget.Button({
            container: this.curationReferenceButtonEl,
            label: 'Curate',
            type: 'button',
            id: 'curation-reference-button',
            onclick: {
                fn: function() {
                    var valid = this.validateInput(this.referenceIDEl.value);
                    if (valid) { 
                        var type;
                        for (var i in this.idTypeCheckboxes ){
                            if (this.idTypeCheckboxes[i].checked == true){
                                type = this.idTypeCheckboxes[i].value;
                            }
                        }          
                        if ( type == undefined ){
                            this.helpPanel.setBody('You have to select ID type first');
                            this.helpPanel.show();
                            YAHOO.log('here','error');
                        }     
                        else {        
                            this.curateReference(this.referenceIDEl.value, type); 
                        }
                    }
                },
                scope: this
            }
        });        
    };

    YAHOO.Dicty.Curation.prototype.curateGene = function(id) {
        location.replace('/curation/gene/' + id);
        return false;   
    };
    YAHOO.Dicty.Curation.prototype.curateReference = function(id,type) {
        if (type == 'pubmed'){
            YAHOO.util.Connect.asyncRequest('GET', '/curation/reference/pubmed/' + id,
            {
                success: function(){
                    location.replace('/curation/reference/pubmed/' + id);
                },
                failure: function(){
                    this.createPubmedDialog.pubmed_id = id;
                    this.createPubmedDialog.show();
                },
                scope: this
            });
        }
        if (type == 'reference_no'){
            location.replace('/curation/reference/' + id);
        }
        return false;   
    };
    YAHOO.Dicty.Curation.prototype.onFailure = function(obj) {
        this.helpPanel.setHeader('Curation Error');
        this.helpPanel.setBody(obj.responseText);
        this.helpPanel.show();

    };
    YAHOO.Dicty.Curation.prototype.validateInput = function(v){
        if (v == undefined || v.match(/\d/) == undefined){
            this.helpPanel.setHeader('Curation Error');
            this.helpPanel.setBody('You have to enter ID first');
            this.helpPanel.show();
            return false;
        }
        return true;
    };
    
})();

function initCuration(v) {
    var curation = new YAHOO.Dicty.Curation();
    curation.init(v);
}