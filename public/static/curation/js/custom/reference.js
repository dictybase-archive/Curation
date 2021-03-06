(function() {
    YAHOO.namespace('Dicty');
    var Dom = YAHOO.util.Dom;
    var Event = YAHOO.util.Event;
    
    YAHOO.Dicty.ReferenceCuration = function() {
       //var logger = new YAHOO.widget.LogReader();
    };

    YAHOO.Dicty.ReferenceCuration.prototype.init = function(id) {
        this.referenceID = id; 
        
        this.linkGenesList = Dom.get('genes-link-list');
        this.linkedGenesList = Dom.get('genes-linked');
        this.linkGenesButtonEl = 'genes-link-button';
        this.unlinkGenesButtonEl = 'genes-unlink-button';
        this.selectAllGenesButtonEl = 'select-all-button';
        this.clearGenesSelectionButtonEl = 'clear-selection-button';
        this.addTopicsButtonEl = 'add-topics-button';
        this.topicCheckboxes = Dom.getElementsByClassName('topics', 'input');
        this.deleteLink = Dom.get('remove-reference');
        
        this.waiting = 0;
        this.message = '';
        
        this.linkGenesButton = new YAHOO.widget.Button({
            container: this.linkGenesButtonEl,
            label: 'Link genes',
            type: 'button',
            id: 'genes-link',
            onclick: {
                fn: function(){ this.genesLink(); },
                scope: this
            }
        });
        this.unlinkGenesButton = new YAHOO.widget.Button({
            container: this.unlinkGenesButtonEl,
            label: 'Unlink selected genes',
            type: 'button',
            id: 'genes-unlink',
            onclick: {
                fn: function(){ this.genesUnlink(); },
                scope: this
            }
        });
        this.selectAllGenesButton = new YAHOO.widget.Button({
            container: this.selectAllGenesButtonEl,
            label: 'Select all genes',
            type: 'button',
            id: 'select-all',
            onclick: {
                fn: function(){ this.selectAllGenes(); },
                scope: this
            }
        });
        this.clearGenesSelectionButton = new YAHOO.widget.Button({
            container: this.clearGenesSelectionButtonEl,
            label: 'Clear genes selection',
            type: 'button',
            id: 'clear-selection',
            onclick: {
                fn: function(){ this.clearGenesSelection(); },
                scope: this
            }
        });
        this.addTopicsButton = new YAHOO.widget.Button({
            container: this.addTopicsButtonEl,
            label: 'Update topics for selected genes',
            type: 'button',
            id: 'add-topics',
            onclick: {
                fn: function(){ this.updateTopics(); },
                scope: this
            }
        });
        this.helpPanel = new YAHOO.widget.Panel("helpPanel", {
            width: "500px",
            visible: false,
            modal: true,
            fixedcenter: true,
            zIndex: 3
        });
        this.helpPanel.setHeader("Reference Curation");
        this.helpPanel.setBody("");
        this.helpPanel.render(document.body);
        this.helpPanelCloseButton = Dom.getElementsByClassName('container-close','a');

        Event.addListener( this.linkGenesList, "click", this.cleanGenesLink, this, this);
        Event.addListener( this.linkedGenesList, "change", this.selectTopics, this, this);
        Event.removeListener(this.deleteLink, "click");
        Event.addListener( this.deleteLink, "click", this.deleteReference, this, this);
        Event.addListener( this.helpPanelCloseButton, "click", function(){
            window.location.reload();
        });
        
        this.clearTopicsSelection();
        this.clearGenesSelection();
    };
    YAHOO.Dicty.ReferenceCuration.prototype.cleanGenesLink = function(f) {
        var initData = Dom.get('genes-link-list').value;
        
        if (initData.match('Paste')) {
            Dom.get('genes-link-list').value = '';
        }
    };
    YAHOO.Dicty.ReferenceCuration.prototype.selectTopics = function() {
        var ids = this.getSelectedGenes();
        if (ids.length > 1) {
            this.clearTopicsSelection();
        }
        else {
            this.getTopicsForGene(ids[0]);
        }
    };
    YAHOO.Dicty.ReferenceCuration.prototype.logResponce = function(obj){
        this.message += '<br/>' + obj.responseText;
        this.waiting--;
        if (this.waiting === 0) {
            this.helpPanel.setBody(this.message);
            this.helpPanel.show();
            this.message = '';
        }
    };
    YAHOO.Dicty.ReferenceCuration.prototype.waitingPanel = function(obj){
        this.helpPanel.setBody("Please wait <img src=\"http://l.yimg.com/a/i/us/per/gr/gp/rel_interstitial_loading.gif\"/>");    
        this.helpPanel.show();
    };    
    YAHOO.Dicty.ReferenceCuration.prototype.genesLink = function() {
        this.waitingPanel();
        
        var ids = this.linkGenesList.value.split(/\r\n|\r|\n| /);
        this.waiting = ids.length;                
        for (var i in ids) {    
            YAHOO.util.Connect.asyncRequest('POST', '/curation/reference/' + this.referenceID + '/gene/' + ids[i],
            {
                success: this.logResponce,
                failure: this.logResponce,
                scope: this
            });
        }
    };
    YAHOO.Dicty.ReferenceCuration.prototype.genesUnlink = function() {
        this.waitingPanel();
        var ids = this.getSelectedGenes();
        
        this.waiting = ids.length;
        for (var i in ids) {    
            YAHOO.util.Connect.asyncRequest('DELETE', '/curation/reference/' + this.referenceID + '/gene/' + ids[i],
            {
                success: this.logResponce,
                failure: this.logResponce,
                scope: this
            });
        }
    };
    YAHOO.Dicty.ReferenceCuration.prototype.selectAllGenes = function() {
        for (var i in this.linkedGenesList.options){
            if (this.linkedGenesList.options[i].value !== undefined){
                this.linkedGenesList.options[i].selected = true;
            }
        }
    };
    YAHOO.Dicty.ReferenceCuration.prototype.clearGenesSelection = function() {
        for (var i in this.linkedGenesList.options){
            this.linkedGenesList.options[i].selected = false;
        }
    };
    YAHOO.Dicty.ReferenceCuration.prototype.getTopicsForGene = function(id) {
        this.waiting = 1;
        this.waitingPanel();
        
        YAHOO.util.Connect.asyncRequest('GET', '/curation/reference/' + this.referenceID + '/gene/' + id + '/topics/',
        {
            success: function(obj) {
                this.clearTopicsSelection();
                var topics = YAHOO.lang.JSON.parse(obj.responseText);                
                for (var i in topics){
                    for (var j in this.topicCheckboxes) {
                        if (this.topicCheckboxes[j].value == topics[i]){
                            this.topicCheckboxes[j].checked = true;
                        }
                    }
                }
                this.helpPanel.hide();
            },
            failure: this.logResponce,
            scope: this
        });
    };
    YAHOO.Dicty.ReferenceCuration.prototype.updateTopics = function() {
        var ids = this.getSelectedGenes();
        var topics = this.getSelectedTopics();
        
        if (ids.length == 0){ return; }
        
        this.waitingPanel();
        this.waiting = ids.length;
        
        for (var i in ids) {  
            YAHOO.util.Connect.asyncRequest('PUT', '/curation/reference/' + this.referenceID + '/gene/' + ids[i] + '/topics/',
            {
                success: this.logResponce,
                failure: this.logResponce,
                scope: this
            },
            YAHOO.lang.JSON.stringify(topics));
        }
    };
    YAHOO.Dicty.ReferenceCuration.prototype.getSelectedGenes = function() {
        var ids = [];
        var linkedGenes = this.linkedGenesList.options;
   
        for (var i in linkedGenes){
            if ( linkedGenes[i].selected) {
                ids.push(linkedGenes[i].value);
            }
        }
        return ids;
    };
    YAHOO.Dicty.ReferenceCuration.prototype.selectAllTopics = function() {
        for (var i in this.topicCheckboxes){
            this.topicCheckboxes[i].checked = true;
        }
    };
    YAHOO.Dicty.ReferenceCuration.prototype.clearTopicsSelection = function() {
        for (var i in this.topicCheckboxes){
            this.topicCheckboxes[i].checked = false;
        }
    };
    YAHOO.Dicty.ReferenceCuration.prototype.getSelectedTopics = function() {
        var ids = [];
        for (var i in this.topicCheckboxes){
            if ( this.topicCheckboxes[i].checked) {
                ids.push(this.topicCheckboxes[i].value);
            }
        }
        return ids;
    };
    YAHOO.Dicty.ReferenceCuration.prototype.deleteReference = function() {
        this.exitPanel = new YAHOO.widget.Panel("exitPanel", {
            width: "500px",
            visible: true,
            modal: true,
            fixedcenter: true,
            zIndex: 3
        });

        this.exitPanel.setHeader("Deleting Reference");
        this.exitPanel.setBody("Please wait <img src=\"http://l.yimg.com/a/i/us/per/gr/gp/rel_interstitial_loading.gif\"/>");
        this.exitPanel.render(document.body);
        this.exitPanel.show();
        this.exitPanel.hideEvent.subscribe( function(){ window.location ='/curation/'; });

        YAHOO.util.Connect.asyncRequest('DELETE', '/curation/reference/' + this.referenceID,
        {
            success: function(obj){
                this.exitPanel.setBody('Reference deleted from database');
            },
            failure: function(obj){
                this.exitPanel.setBody('Error deleting reference: ' + obj.responseText);
            },
            scope: this
        });
        
    };

/*  not used any more, moved to bulk update from one-by-one

    YAHOO.Dicty.ReferenceCuration.prototype.addTopics = function() {
//        this.waitingPanel();
        var ids = this.getSelectedGenes();
        var topics = this.getSelectedTopics();
        
        this.waiting = ids.length * topics.length;
        
        for (var i in ids) {    
            for (var j in topics) {
                YAHOO.util.Connect.asyncRequest('POST', '/curation/reference/' + this.referenceID + '/gene/' + ids[i] + '/topics/',
                {
                    success: this.logResponce,
                    failure: this.logResponce,
                    scope: this
                },
                topics[j]);
            }
        }
    };
    YAHOO.Dicty.ReferenceCuration.prototype.deleteTopics = function() {
        this.waitingPanel();
        var ids = this.getSelectedGenes();
        var topics = this.getSelectedTopics();
        
        this.waiting = ids.length * topics.length;
        
        for (var i in ids) {    
            for (var j in topics) {
                YAHOO.util.Connect.asyncRequest('DELETE', '/curation/reference/' + this.referenceID + '/gene/' + ids[i] + '/topics/' + topics[j],
                {
                    success: this.logResponce,
                    failure: this.logResponce,
                    scope: this
                });
            }
        }
    };

*/

})();

function initReferenceCuration(v) {
    var curation = new YAHOO.Dicty.ReferenceCuration();
    curation.init(v);
}