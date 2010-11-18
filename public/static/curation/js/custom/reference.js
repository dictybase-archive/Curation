(function() {
    YAHOO.namespace('Dicty');
    var Dom = YAHOO.util.Dom;
    var Event = YAHOO.util.Event;
    
    YAHOO.Dicty.ReferenceCuration = function() {
       var logger = new YAHOO.widget.LogReader();
    };

    YAHOO.Dicty.ReferenceCuration.prototype.init = function(id) {
        this.referenceID = id; 
        
        this.linkGenesList = Dom.get('genes-link-list');
        this.linkedGenesList = Dom.get('genes-linked');
        this.linkGenesButtonEl = 'genes-link-button';
        this.unlinkGenesButtonEl = 'genes-unlink-button';
        this.selectAllButtonEl = 'select-all-button';
        this.clearSelectionButtonEl = 'clear-selection-button';
        
        this.waiting = 0;
        this.message = '';
        
        this.linkGenesButton = new YAHOO.widget.Button({
            container: this.linkGenesButtonEl,
            label: 'Link',
            type: 'button',
            id: 'genes-link',
            onclick: {
                fn: function(){ this.genesLink(); },
                scope: this
            }
        });
        this.unlinkGenesButton = new YAHOO.widget.Button({
            container: this.unlinkGenesButtonEl,
            label: 'Unlink',
            type: 'button',
            id: 'genes-unlink',
            onclick: {
                fn: function(){ this.genesUnlink(); },
                scope: this
            }
        });
        this.selectAllButton = new YAHOO.widget.Button({
            container: this.selectAllButtonEl,
            label: 'Select all genes',
            type: 'button',
            id: 'select-all',
            onclick: {
                fn: function(){ this.selectAll(); },
                scope: this
            }
        });
        this.clearSelectionButton = new YAHOO.widget.Button({
            container: this.clearSelectionButtonEl,
            label: 'Clear selection',
            type: 'button',
            id: 'clear-selection',
            onclick: {
                fn: function(){ this.clearSelection(); },
                scope: this
            }
        });
        this.helpPanel = new YAHOO.widget.Panel("helpPanel", {
            width: "500px",
            visible: true,
            modal: true,
            fixedcenter: true,
            zIndex: 3
        });
        this.helpPanel.setHeader("Gene Curation");
        
        YAHOO.util.Event.addFocusListener(this.linkGenesList.id, function() {
            var initData = Dom.get('genes-link-list').value;
            if (initData.match('Paste')) {
                Dom.get('genes-link-list').value = '';
            }
        });
    };
    
    YAHOO.Dicty.ReferenceCuration.prototype.logResponce = function(obj){
        this.message += '<br/>' + obj.responseText;
        this.waiting--;
        if (this.waiting == 0) {
            this.helpPanel.setBody(this.message);
            this.helpPanel.cfg.setProperty("visible","true");

            this.helpPanel.render(document.body);
            this.helpPanel.show();

            this.message = '';
        }
    }

    YAHOO.Dicty.ReferenceCuration.prototype.genesLink = function() {
        var ids = this.linkGenesList.value.split(/\r\n|\r|\n| /);
        this.waiting = ids.length;                
        for (var i in ids) {    
            YAHOO.util.Connect.asyncRequest('POST', '/curation/reference/' + this.referenceID + '/' + ids[i],
            {
                success: this.logResponce,
                failure: this.logResponce,
                scope: this
            });
        }
    };

    YAHOO.Dicty.ReferenceCuration.prototype.genesUnlink = function() {
        var ids = new Array();
        var linkedGenes = this.linkedGenesList.options;
   
        for (var i in linkedGenes){
            if ( linkedGenes[i].selected) {
                ids.push(linkedGenes[i].value);
            }
        }
        this.waiting = ids.length;
        for (var i in ids) {    
            YAHOO.util.Connect.asyncRequest('DELETE', '/curation/reference/' + this.referenceID + '/' + ids[i],
            {
                success: this.logResponce,
                failure: this.logResponce,
                scope: this
            });
        }
    };
    
    YAHOO.Dicty.ReferenceCuration.prototype.selectAll = function() {
        for (var i in this.linkedGenesList.options){
            this.linkedGenesList.options[i].selected = true;
        }
    };
    
    YAHOO.Dicty.ReferenceCuration.prototype.clearSelection = function() {
        for (var i in this.linkedGenesList.options){
            this.linkedGenesList.options[i].selected = false;
        }
    }
})();

function initReferenceCuration(v) {
    var curation = new YAHOO.Dicty.ReferenceCuration();
    curation.init(v);
}