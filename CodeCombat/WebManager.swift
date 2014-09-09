//
//  WebManager.swift
//  iPadClient
//
//  Created by Michael Schmatz on 7/26/14.
//  Copyright (c) 2014 CodeCombat. All rights reserved.
//

import UIKit
import WebKit
class WebManager: NSObject, WKScriptMessageHandler {
  
  var webViewConfiguration: WKWebViewConfiguration!
  var urlSesssionConfiguration: NSURLSessionConfiguration?
  let rootURL = NSURL(scheme: "http", host: "localhost:3000", path: "/")
  //let rootURL = NSURL(scheme: "http", host: "10.0.1.2:3000", path: "/")
  var operationQueue: NSOperationQueue?
  var webView: WKWebView?  // Assign this if we create one, so that we can evaluate JS in its context.
  //let webViewContextPointer = UnsafeMutablePointer<()>()
  var lastJSEvaluated: String?
  
  var scriptMessageNotificationCenter:NSNotificationCenter!
  class var sharedInstance:WebManager {
    return WebManagerSharedInstance
  }

  override init() {
    super.init()
    operationQueue = NSOperationQueue()
    scriptMessageNotificationCenter = NSNotificationCenter()
    instantiateWebView()
    subscribe(self, channel: "application:error", selector: "onJSError:")
  }
  
  private func instantiateWebView() {
    let WebViewFrame = CGRectMake(0, 0, 1024, 1024 * (589 / 924))  // Full-width Surface, preserving aspect ratio.
    webViewConfiguration = WKWebViewConfiguration()
    addScriptMessageHandlers()
    webView = WKWebView(frame: WebViewFrame, configuration: webViewConfiguration)
    webView!.hidden = true
    if let email = User.sharedInstance.email {
      logIn(email: email, password: User.sharedInstance.password!)
    }
  }
  
  func logIn(#email: String, password: String) {
    let loginScript = "function foobarbaz() { require('/lib/auth').loginUser({'email':'\(email)','password':'\(password)'}); } if(me.get('anonymous')) setTimeout(foobarbaz, 1);"
    let userScript = WKUserScript(source: loginScript, injectionTime: .AtDocumentEnd, forMainFrameOnly: true)
    webViewConfiguration!.userContentController.addUserScript(userScript)
    let requestURL = NSURL(string: "/", relativeToURL: rootURL)
    let request = NSMutableURLRequest(URL: requestURL)
    webView!.loadRequest(request)
    //addWebViewKeyValueObservers()
    //println("going to log in to \(requestURL) when web view loads! \(loginScript)")
  }
  
  /*
  func addWebViewKeyValueObservers() {
    webView!.addObserver(self,
      forKeyPath: NSStringFromSelector(Selector("loading")),
      options: nil,
      context: webViewContextPointer)
    webView!.addObserver(self,
      forKeyPath: NSStringFromSelector(Selector("estimatedProgress")),
      options: NSKeyValueObservingOptions.Initial,
      context: webViewContextPointer)
  }

  override func observeValueForKeyPath(
    keyPath: String!,
    ofObject object: AnyObject!,
    change: [NSObject : AnyObject]!, context: UnsafeMutablePointer<()>) {
      if context == WebViewContextPointer {
        switch keyPath! {
          //case NSStringFromSelector(Selector("estimatedProgress")):
          //if webView!.estimatedProgress > 0.8 && !injectedListeners {
          //  injectListeners()
          //}
        default:
          println("\(keyPath) changed")
        }
      } else {
        super.observeValueForKeyPath(keyPath,
          ofObject: object,
          change: change,
          context: context)
      }
  }
  
  func doLogIn(loginScript: String) {
    println("going to log in with \(loginScript)")
    evaluateJavaScript(loginScript, completionHandler: { response, error in
      if error != nil {
        println("There was an error evaluating JS: \(error), response: \(response)")
      } else {
        //hasLoggedIn = true
        //isLoggingIn = false
        println("Logging in! Got JS response: \(response)")
        //webpageLoadingProgressView.setProgress(0.2, animated: true)
      }
    })
  }
  */
  
  func subscribe(observer: AnyObject, channel: String, selector: Selector) {
    scriptMessageNotificationCenter.addObserver(observer, selector: selector, name: channel, object: self)
  }
  
  func unsubscribe(observer: AnyObject) {
    scriptMessageNotificationCenter.removeObserver(observer)
  }
  
  func publish(channel: String, event: Dictionary<String, AnyObject>) {
    let serializedEvent = serializeData(event)
    evaluateJavaScript("Backbone.Mediator.publish('\(channel)', \(serializedEvent))", onJSEvaluated)
  }
  
  func evaluateJavaScript(js: String, completionHandler: ((AnyObject!, NSError!) -> Void)!) {
    var handler = completionHandler == nil ? onJSEvaluated : completionHandler  // There's got to be a more Swifty way of doing this.
    lastJSEvaluated = js
    //println(" evaluating JS: \(js)")
    webView?.evaluateJavaScript(js, completionHandler: handler)  // This isn't documented, so is it being added or removed or what?
  }
  
  func onJSEvaluated(response: AnyObject!, error: NSError?) {
    if error != nil {
      println("There was an error evaluating JS: \(error), response: \(response)")
      println("JS was \(lastJSEvaluated!)")
    } else if response != nil {
      println("Got response from evaluating JS: \(response)")
    }
  }
  
  func onJSError(note: NSNotification) {
    if let event = note.userInfo {
      let message = event["message"]! as String
      println("💔💔💔 Unhandled JS error in application: \(message)")
    }
  }
  
  private func serializeData(data:NSDictionary?) -> String {
    var serialized:NSData?
    var error:NSError?
    if data != nil {
      serialized = NSJSONSerialization.dataWithJSONObject(data!, options: NSJSONWritingOptions(0), error: &error)
    } else {
      let EmptyObjectString = NSString(string: "{}")
      serialized = EmptyObjectString.dataUsingEncoding(NSUTF8StringEncoding)
    }
    return NSString(data: serialized!, encoding: NSUTF8StringEncoding)
  }
  
  func userContentController(userContentController: WKUserContentController!, didReceiveScriptMessage message: WKScriptMessage!) {
    if message.name == "backboneEventHandler" {
      // Turn Backbone events into NSNotifications
      let body = (message.body as NSDictionary) as Dictionary  // You... It... So help me...
      let channel = body["channel"] as NSString
      let event = (body["event"] as NSDictionary) as Dictionary
      //println("got backbone event: \(channel)")
      scriptMessageNotificationCenter.postNotificationName(channel, object: self, userInfo: event)
    } else if message.name == "consoleLogHandler" {
      let body = (message.body as NSDictionary) as Dictionary
      let level = body["level"] as NSString
      let arguments = body["arguments"] as NSArray
      let message = arguments.componentsJoinedByString(" ")
      println("\(colorEmoji[level]!) \(level): \(message)")
    }
    else {
      println("got message: \(message.name): \(message.body)")
      scriptMessageNotificationCenter.postNotificationName(message.name, object: self, userInfo: message.body as? NSDictionary)
    }
  }
  
  func addScriptMessageHandlers() {
    let contentController = webViewConfiguration!.userContentController
    contentController.addScriptMessageHandler(self, name: "backboneEventHandler")
    contentController.addScriptMessageHandler(self, name: "consoleLogHandler")
  }
}

let WebManagerSharedInstance = WebManager()

let colorEmoji = ["debug": "📘", "log": "📓", "info": "📔", "warn": "📙", "error": "📕"]
//var emoji = "↖↗↘↙⏩⏪▶◀☀☁☎☔☕☝☺♈♉♊♋♌♍♎♏♐♑♒♓♠♣♥♦♨♿⚠⚡⚽⚾⛄⛎⛪⛲⛳⛵⛺⛽✂✈✊✋✌✨✳✴❌❎❓❔❕❗❤➡➿⬅⬆⬇⭐⭕〽㊗㊙🀄🅰🅱🅾🅿🆎🆒🆔🆕🆗🆙🆚🈁🈂🈚🈯🈳🈵🈶🈷🈸🈹🈺🉐🌀🌂🌃🌄🌅🌆🌇🌈🌊🌙🌟🌴🌵🌷🌸🌹🌺🌻🌾🍀🍁🍂🍃🍅🍆🍉🍊🍎🍓🍔🍘🍙🍚🍛🍜🍝🍞🍟🍡🍢🍣🍦🍧🍰🍱🍲🍳🍴🍵🍶🍸🍺🍻🎀🎁🎂🎃🎄🎅🎆🎇🎈🎉🎌🎍🎎🎏🎐🎑🎒🎓🎡🎢🎤🎥🎦🎧🎨🎩🎫🎬🎯🎰🎱🎵🎶🎷🎸🎺🎾🎿🏀🏁🏃🏄🏆🏈🏊🏠🏢🏣🏥🏦🏧🏨🏩🏪🏫🏬🏭🏯🏰🐍🐎🐑🐒🐔🐗🐘🐙🐚🐛🐟🐠🐤🐦🐧🐨🐫🐬🐭🐮🐯🐰🐱🐳🐴🐵🐶🐷🐸🐹🐺🐻👀👂👃👄👆👇👈👉👊👋👌👍👎👏👐👑👒👔👕👗👘👙👜👟👠👡👢👣👦👧👨👩👫👮👯👱👲👳👴👵👶👷👸👻👼👽👾👿💀💁💂💃💄💅💆💇💈💉💊💋💍💎💏💐💑💒💓💔💗💘💙💚💛💜💝💟💡💢💣💤💦💨💩💪💰💱💹💺💻💼💽💿📀📖📝📠📡📢📣📩📫📮📱📲📳📴📶📷📺📻📼🔊🔍🔑🔒🔓🔔🔝🔞🔥🔨🔫🔯🔰🔱🔲🔳🔴🕐🕑🕒🕓🕔🕕🕖🕗🕘🕙🕚🕛🗻🗼🗽😁😂😃😄😉😊😌😍😏😒😓😔😖😘😚😜😝😞😠😡😢😣😥😨😪😭😰😱😲😳😷🙅🙆🙇🙌🙏🚀🚃🚄🚅🚇🚉🚌🚏🚑🚒🚓🚕🚗🚙🚚🚢🚤🚥🚧🚬🚭🚲🚶🚹🚺🚻🚼🚽🚾🛀⏫⏬⏰⏳✅➕➖➗➰🃏🆑🆓🆖🆘🇦🇧🇨🇩🇪🇫🇬🇭🇮🇯🇰🇱🇲🇳🇴🇵🇶🇷🇸🇹🇺🇻🇼🇽🇾🇿🈲🈴🉑🌁🌉🌋🌌🌏🌑🌓🌔🌕🌛🌠🌰🌱🌼🌽🌿🍄🍇🍈🍌🍍🍏🍑🍒🍕🍖🍗🍠🍤🍥🍨🍩🍪🍫🍬🍭🍮🍯🍷🍹🎊🎋🎠🎣🎪🎭🎮🎲🎳🎴🎹🎻🎼🎽🏂🏡🏮🐌🐜🐝🐞🐡🐢🐣🐥🐩🐲🐼🐽🐾👅👓👖👚👛👝👞👤👪👰👹👺💌💕💖💞💠💥💧💫💬💮💯💲💳💴💵💸💾📁📂📃📄📅📆📇📈📉📊📋📌📍📎📏📐📑📒📓📔📕📗📘📙📚📛📜📞📟📤📥📦📧📨📪📰📹🔃🔋🔌🔎🔏🔐🔖🔗🔘🔙🔚🔛🔜🔟🔠🔡🔢🔣🔤🔦🔧🔩🔪🔮🔵🔶🔷🔸🔹🔼🔽🗾🗿😅😆😋😤😩😫😵😸😹😺😻😼😽😾😿🙀🙈🙉🙊🙋🙍🙎🚨🚩🚪🚫"