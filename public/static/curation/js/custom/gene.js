(function() {
    YAHOO.namespace('Dicty');
    var Dom = YAHOO.util.Dom;
    var Event = YAHOO.util.Event;
    
    YAHOO.Dicty.GeneCuration = function() {
       // var logger = new YAHOO.widget.LogReader();
    };

    YAHOO.Dicty.GeneCuration.prototype.init = function(id) {
        this.geneID = id; 
        this.autoload = 'autoload';
        this.qualifier = 'qualifier'; 
        this.tab = 'tab';   
        
        this.loadAutoloads();
            
        this.curationApproveButtonEl = 'curation-approve';
        this.curationImpossibleButtonEl = 'curation-impossible';
        
        this.curationApproveButton = new YAHOO.widget.Button({
            container: this.curationApproveButtonEl,
            label: 'Approve',
            type: 'button',
            id: 'curation-approve',
            onclick: {
                fn: function(){ this.curate(); },
                scope: this
            }
        });
        this.curationImpossibleButton = new YAHOO.widget.Button({
            container: this.curationImpossibleButtonEl,
            label: 'Skip',
            type: 'button',
            id: 'curation-impossible',
            onclick: {
                fn: function(){ this.giveup(); },
                scope: this
            }
        });
    };
    
    YAHOO.Dicty.GeneCuration.prototype.curate = function() {
        var postData = '';
        var qualifierNodes = Dom.getElementsByClassName( 'qualifier' );
        var featureNodes   = Dom.getElementsByClassName( 'feature' );
        
        for (var i in qualifierNodes) {     
            if (qualifierNodes[i].checked){
                postData += qualifierNodes[i].id + '=' + 1 + '&';
            }
        }
        var featuresPost;
        for (var i in featureNodes) {     
            if (featureNodes[i].checked){
                featuresPost = featureNodes[i].id;
            }
        }
        postData = postData + 'feature=' + featuresPost;

        YAHOO.util.Connect.asyncRequest('POST', '/curation/gene/' + this.geneID + '/update/',
        {
            success: function(obj) {
                var helpPanel = new YAHOO.widget.Panel("helpPanel", {
                    width: "500px",
                    visible: true,
                    modal: true,
                    fixedcenter: true,
                    zIndex: 3
                });
                helpPanel.setHeader("Gene Curation");
                helpPanel.setBody(obj.responseText);
                helpPanel.render(document.body);
            },
            failure: this.onFailure,
            scope: this
        },
        postData);
    
        YAHOO.util.Connect.asyncRequest('DELETE', '/cache/gene/' + this.geneID);
    };
    YAHOO.Dicty.GeneCuration.prototype.onFailure = function(obj) {
        //alert(obj.statusText);
    };
    YAHOO.Dicty.GeneCuration.prototype.giveup = function() {
        var postData = '';
        YAHOO.util.Connect.asyncRequest('POST', '/curation/gene/' + this.geneID + '/skip/',
        {
            success: function(obj) {
                var helpPanel = new YAHOO.widget.Panel("helpPanel", {
                    width: "500px",
                    visible: true,
                    modal: true,
                    fixedcenter: true,
                    zIndex: 3
                });
                helpPanel.setHeader("Gene Curation");
                helpPanel.setBody(obj.responseText);
                helpPanel.render(document.body);
            },
            failure: this.onFailure,
            scope: this
        },
        postData);
    
        YAHOO.util.Connect.asyncRequest('DELETE', '/cache/gene/' + this.geneID);
    };
    YAHOO.Dicty.GeneCuration.prototype.loadAutoloads = function() {
        var autoloadNodes = Dom.getElementsByClassName(this.autoload);
        for (var i in autoloadNodes) {
            var args = [autoloadNodes[i].id];
            YAHOO.util.Connect.asyncRequest('GET', '/curation/gene/' + this.geneID + '/' + autoloadNodes[i].id,
            {
                success: function(obj) {
                    Dom.get(obj.argument[0]).innerHTML = obj.responseText;
                    var tabNodes = Dom.getElementsByClassName(this.tab);
                    for (var j in tabNodes){
                        new YAHOO.widget.TabView(tabNodes[j].id);
                        Dom.removeClass(tabNodes[j], this.tab);
                    }
                },
                failure: this.onFailure,
                scope: this,
                argument : args
            });
        }
    }
})();

function initGeneCuration(v) {
    var curation = new YAHOO.Dicty.GeneCuration;
    curation.init(v);
}