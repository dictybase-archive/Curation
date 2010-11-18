(function() {
    YAHOO.namespace('Dicty');
    var Dom = YAHOO.util.Dom;
    var Event = YAHOO.util.Event;

    YAHOO.Dicty.Curation = function() {
        //var logger = new YAHOO.widget.LogReader();
    };

    YAHOO.Dicty.Curation.prototype.init = function() {
        this.geneIDEl = Dom.get('gene-id');
        this.referenceIDEl = Dom.get('pubmed-id');
        this.curationReferenceButtonEl = 'curation-reference';
        this.curationGeneButtonEl = 'curation-gene';

        this.helpPanel = new YAHOO.widget.Panel("helpPanel", {
            width: "500px",
            visible: true,
            modal: true,
            fixedcenter: true,
            zIndex: 3,
            visible: false
        });
        
        this.curationGeneButton = new YAHOO.widget.Button({
            container: this.curationGeneButtonEl,
            label: 'Curate',
            type: 'button',
            id: 'curation-gene-button',
            onclick: {
                fn: function() {
                    var valid = this.validateInput(this.geneIDEl.value);
                    if (valid) { this.curateGene(this.geneIDEl.value); }
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
                    if (valid) { this.curateReference(this.referenceIDEl.value); }
                },
                scope: this
            }
        });
    };

    YAHOO.Dicty.Curation.prototype.curateGene = function(id) {
        location.replace('/curation/gene/' + id);
        return false;   
    };
    YAHOO.Dicty.Curation.prototype.curateReference = function(id) {
        location.replace('/curation/reference/' + id);
        return false;   
    };
    YAHOO.Dicty.Curation.prototype.onFailure = function(obj) {
        //alert(obj.statusText);
    };
    YAHOO.Dicty.Curation.prototype.validateInput = function(v){
        if (v == undefined || v.match(/\d/) == undefined){
            this.helpPanel.setHeader('Curation Error');
            this.helpPanel.setBody('You have to enter ID first');
            this.helpPanel.render(document.body);
            this.helpPanel.cfg.setProperty('visible',true);
            return false;
        }
        return true;
    }
    
})();

function initCuration(v) {
    var curation = new YAHOO.Dicty.Curation;
    curation.init(v);
}