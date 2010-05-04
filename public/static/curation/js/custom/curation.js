(function() {
    YAHOO.namespace('Dicty');
    var Dom = YAHOO.util.Dom;
    var Event = YAHOO.util.Event;
    
    YAHOO.Dicty.Curation = function() {
//        var logger = new YAHOO.widget.LogReader();
    };

//    YAHOO.lang.augmentProto(YAHOO.Dicty.Curation, YAHOO.util.AttributeProvider);
    
    YAHOO.Dicty.Curation.prototype.init = function(id) {
        this.geneID = id; 
        this.searchButtonEl = 'search-submit';
        this.searchInput    = Dom.get('gene-id');
        
        this.supportedByEST = Dom.get('supported-by-est');
        this.supportedBySS = Dom.get('supported-by-ss');
        this.supportedByGC = Dom.get('supported-by-gc');
        this.supportedByUTS = Dom.get('supported-by-uts');
        
        this.curationApproveButtonEl = 'curation-approve';
        this.autoload = 'autoload';
        
        this.searchButton = new YAHOO.widget.Button({
            container: this.searchButtonEl,
            label: 'Search',
            type: 'button',
            id: 'run-search',
            onclick: {
                fn: function(){ this.search(this.searchInput.value) },
                scope: this
            }
        });
        this.curationApproveButton = new YAHOO.widget.Button({
            container: this.curationApproveButtonEl,
            label: 'Approve',
            type: 'button',
            id: 'curation-approve',
            onclick: {
                fn: function(){ this.curate(this.supportedByEST.checked, this.supportedBySS.checked, this.supportedByGC.checked, this.supportedByUTS.checked ) },
                scope: this
            }
        });
        var autoloadNodes = Dom.getElementsByClassName(this.autoload);
        for (i in autoloadNodes) {
            var args = [autoloadNodes[i].id];
            
            YAHOO.util.Connect.asyncRequest('GET', '/curation/gene/' + this.geneID + '/' + autoloadNodes[i].id,
            {
                success: function(obj) {
                    Dom.get(obj.argument[0]).innerHTML = obj.responseText;
                },
                failure: this.onFailure,
                scope: this,
                argument : args
            });
        }
    };
    
    YAHOO.Dicty.Curation.prototype.curate = function(estSupport, ssSupport, gcSupport, utsSupport) {
        var postData = 'estSupport=' + estSupport +
            '&ssSupport=' + ssSupport +
            '&gcSupport=' + gcSupport +
            '&utsSupport=' + utsSupport;

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
    };
    YAHOO.Dicty.Curation.prototype.onFailure = function(obj) {
        alert(obj.statusText);
    }
})();

function init(v) {
    var curation = new YAHOO.Dicty.Curation;
    curation.init(v);
}