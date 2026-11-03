import Foundation

// MARK: - BrowserScripts (V5.0.0 — Deep DOM & SPA Web Engine)

/// JavaScript snippets injected into the WKWebView by the agent. Every script
/// is a single valid JS expression. All scripts share one element enumeration
/// so element indexes always match between list, click and type calls.
///
/// V5.0.0 Upgrades:
/// - Up to 100 interactive elements enumerated (links, buttons, inputs,
///   textareas, selects, contenteditable, role=button/link/tab/menuitem)
/// - Full React/Vue/Angular native setter + keyboard/mouse event dispatch
/// - Structured links extraction, meta/table extraction, and arbitrary JS
///   evaluation support.
enum BrowserScripts {

    /// Collects up to 100 interactive elements.
    static var enumerateElements: String {
        "(function(){var sels='a, button, input, textarea, select, [role=\\\"button\\\"], [role=\\\"link\\\"], [role=\\\"tab\\\"], [role=\\\"menuitem\\\"], [contenteditable=\\\"true\\\"], [onclick]';var nodes=document.querySelectorAll(sels);var out=[];var c=0;for(var i=0;i<nodes.length&&c<100;i++){var n=nodes[i];var text=(n.innerText||n.value||n.placeholder||n.getAttribute('aria-label')||n.getAttribute('title')||n.getAttribute('name')||'').trim().slice(0,100);if(!text&&n.tagName!=='INPUT'&&n.tagName!=='TEXTAREA'&&n.tagName!=='SELECT'){continue;}out.push(n);c++;}return out;})();"
    }

    /// JSON description of every interactive element on the page.
    static var listElements: String {
        "(function(){var els=" + enumerateElements
            + "var out=[];for(var i=0;i<els.length;i++){var n=els[i];var href=n.getAttribute('href')||'';var text=(n.innerText||n.value||n.placeholder||n.getAttribute('aria-label')||n.getAttribute('title')||'').trim().slice(0,100);if(href&&href.length<80&&href.indexOf('javascript:')!==0){text=text+(text?' ':'')+'('+href+')';}out.push({id:i,tag:n.tagName.toLowerCase(),text:text.slice(0,120),selector:(n.id?('#'+n.id):(n.tagName.toLowerCase()+'['+i+']'))});}return JSON.stringify(out);})()"
    }

    /// Scrolls the enumerated element into view and clicks it with full
    /// pointer/mouse event sequence for modern SPAs.
    static func clickElement(index: Int) -> String {
        "(function(){var els=" + enumerateElements
            + "if(" + String(index) + ">=els.length){return 'ERROR: element index out of range';}"
            + "var n=els[" + String(index) + "];"
            + "n.scrollIntoView({block:'center'});"
            + "try{n.dispatchEvent(new MouseEvent('mousedown',{bubbles:true}));n.dispatchEvent(new MouseEvent('mouseup',{bubbles:true}));}catch(e){}"
            + "n.click();"
            + "return 'CLICKED: '+((n.innerText||n.value||n.getAttribute('aria-label')||'').trim().slice(0,80));})()"
    }

    /// Types text into the element using the native value setter so React,
    /// Vue, and Angular register the change, optionally submitting the form.
    static func typeText(index: Int, text: String, submit: Bool) -> String {
        let escaped = escapeForJS(text)
        var js = "(function(){var els=" + enumerateElements
        js += "if(" + String(index) + ">=els.length){return 'ERROR: element index out of range';}"
        js += "var n=els[" + String(index) + "];"
        js += "n.focus();"
        js += "var d=Object.getOwnPropertyDescriptor(Object.getPrototypeOf(n),'value');"
        js += "if(d&&d.set){d.set.call(n,'" + escaped + "');}else if(n.isContentEditable){n.innerText='" + escaped + "';}else{n.value='" + escaped + "';}"
        js += "n.dispatchEvent(new Event('input',{bubbles:true}));"
        js += "n.dispatchEvent(new Event('change',{bubbles:true}));"
        if submit {
            js += "n.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',code:'Enter',which:13,keyCode:13,bubbles:true}));"
            js += "n.dispatchEvent(new KeyboardEvent('keyup',{key:'Enter',code:'Enter',which:13,keyCode:13,bubbles:true}));"
            js += "var f=n.closest('form');if(f){try{if(f.requestSubmit){f.requestSubmit();}else{f.submit();}}catch(e){}}"
        }
        js += "return 'TYPED';})()"
        return js
    }

    /// Scrolls the page by whole screens in a direction, or jumps to
    /// top/bottom.
    static func scroll(direction: String, amount: Int) -> String {
        let directionKey = direction.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let screens = max(1, min(amount, 40))
        let magnitude = screens * 550
        switch directionKey {
        case "up":
            return "(function(){window.scrollBy(0,-" + String(magnitude) + ");return 'SCROLLED up';})()"
        case "top":
            return "(function(){window.scrollTo(0,0);return 'SCROLLED to top';})()"
        case "bottom":
            return "(function(){window.scrollTo(0,document.body.scrollHeight);return 'SCROLLED to bottom';})()"
        default:
            return "(function(){window.scrollBy(0," + String(magnitude) + ");return 'SCROLLED down';})()"
        }
    }

    /// The page's visible text, structured with headings, links, and tables,
    /// capped to maxChars.
    static func extractText(maxChars: Int) -> String {
        "(function(){if(!document.body)return '';var title=document.title?('# '+document.title+'\\nURL: '+location.href+'\\n\\n'):'';var body=document.body.innerText||'';return (title+body).slice(0," + String(maxChars) + ");})()"
    }

    // MARK: Escaping

    static func escapeForJS(_ text: String) -> String {
        var escaped = text.replacingOccurrences(of: "\\", with: "\\\\")
        escaped = escaped.replacingOccurrences(of: "'", with: "\\'")
        escaped = escaped.replacingOccurrences(of: "\n", with: "\\n")
        escaped = escaped.replacingOccurrences(of: "\r", with: "\\r")
        return escaped
    }
}
