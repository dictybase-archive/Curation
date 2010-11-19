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
        this.selectAllGenesButtonEl = 'select-all-button';
        this.clearGenesSelectionButtonEl = 'clear-selection-button';
        this.addTopicsButtonEl = 'add-topics-button';
        this.topicCheckboxes = Dom.getElementsByClassName('topics', 'input');
        
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
            label: 'Unlink selected',
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
            label: 'Clear selection',
            type: 'button',
            id: 'clear-selection',
            onclick: {
                fn: function(){ this.clearGenesSelection(); },
                scope: this
            }
        });
        this.addTopicsButton = new YAHOO.widget.Button({
            container: this.addTopicsButtonEl,
            label: 'Add topics to selected',
            type: 'button',
            id: 'add-topics',
            onclick: {
                fn: function(){ this.addTopics(); },
                scope: this
            }
        });
        this.helpPanel = new YAHOO.widget.Panel("helpPanel", {
            width: "500px",
            visible: false,
            modal: true,
            fixedcenter: false,
            zIndex: 3
        });
        this.helpPanel.setHeader("Gene Curation");
        this.helpPanel.setBody("");
        this.helpPanel.render(document.body);
        
        YAHOO.util.Event.addListener(this.linkGenesList.id, "click", function() {
            var initData = Dom.get('genes-link-list').value;
            if (initData.match('Paste')) {
                Dom.get('genes-link-list').value = '';
            }
        });

        YAHOO.util.Event.addListener( this.linkedGenesList, "change", this.selectTopics, this, this);
        this.clearTopicsSelection();
    };
    YAHOO.Dicty.ReferenceCuration.prototype.selectTopics = function() {
        var ids = this.getSelectedGenes();
        YAHOO.log('here');
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
            //this.helpPanel.hideEvent(window.location.reload());
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
        this.waitingPanel;
        
        YAHOO.util.Connect.asyncRequest('GET', '/curation/reference/' + this.referenceID + '/gene/' + id + '/topics/',
        {
            success: function(obj) {
                this.clearTopicsSelection();
                var topics = YAHOO.lang.JSON.parse(obj.responseText);
                YAHOO.log(this.topicCheckboxes);
                
                for (var i in topics){
                    YAHOO.log(topics[i], 'error');
                    for (var j in this.topicCheckboxes) {
                        YAHOO.log(this.topicCheckboxes[j].value + ':' + topics[i], 'error');
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
    YAHOO.Dicty.ReferenceCuration.prototype.getSelectedTopics = function() {
        var ids = [];
        for (var i in this.topicCheckboxes){
            if ( this.topicCheckboxes[i].checked) {
                ids.push(this.topicCheckboxes[i].value);
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
})();

function initReferenceCuration(v) {
    var curation = new YAHOO.Dicty.ReferenceCuration();
    curation.init(v);
}