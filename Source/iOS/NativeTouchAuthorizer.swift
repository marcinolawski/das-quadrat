//
//  NativeTouchAuthorizer.swift
//  Quadrat
//
//  Created by Constantine Fry on 12/11/14.
//  Copyright (c) 2014 Constantine Fry. All rights reserved.
//

import Foundation
import UIKit

class NativeTouchAuthorizer: Authorizer {
    private var configuration: Configuration!
    
    /** Network activity controller. */
    private var networkActivityController: NetworkActivityIndicatorController?
    
    convenience init(configuration: Configuration) {
        let baseURL = configuration.server.nativeOauthBaseURL
        let parameters = [
            Parameter.client_id    : configuration.client.identifier,
            Parameter.redirect_uri : configuration.client.redirectURL,
            Parameter.v            : "20130509"
        ]
        
        let authorizationURL = Parameter.buildURL(NSURL(string: baseURL)!, parameters: parameters)
        let redirectURL = NSURL(string: configuration.client.redirectURL)
        if redirectURL == nil {
            fatalError("Check your redirectURL")
        }
        let keychain = Keychain(configuration: configuration)
        self.init(authorizationURL: authorizationURL, redirectURL: redirectURL!, keychain:keychain)
        self.configuration = configuration
        if configuration.shouldControllNetworkActivityIndicator {
            networkActivityController = NetworkActivityIndicatorController()
        }
    }
    
    func authorize(completionHandler: (String?, NSError?) -> Void) {
        self.completionHandler = completionHandler
        UIApplication.sharedApplication().openURL(self.authorizationURL)
    }
    
    func handleURL(URL: NSURL) -> Bool {
        if URL.scheme == self.redirectURL.scheme {
            self.didReachRedirectURL(URL)
            return true
        }
        return false
    }
    
    override func didReachRedirectURL(redirectURL: NSURL) {
        let parameters = self.extractParametersFromURL(redirectURL)
        let accessCode = parameters["code"]
        if let accessCode = accessCode {
            // We should exchange access code to access token.
            self.requestAccessTokenWithCode(accessCode)
        } else {
            // No access code, so we have error there. This method will take care about it.
            super.didReachRedirectURL(redirectURL)
        }
    }
    
    func requestAccessTokenWithCode(code: String) {
        let accessTokenURL = self.configuration.server.nativeOauthAccessTokenBaseURL
        
        let client = self.configuration.client
        let parameters = [
            Parameter.client_id     : client.identifier,
            Parameter.client_secret : client.secret,
            Parameter.redirect_uri  : client.redirectURL,
            Parameter.code          : code,
            Parameter.grant_type    : "authorization_code"
        ]
        let URL = Parameter.buildURL(NSURL(string: accessTokenURL)!, parameters: parameters)
        let request = NSURLRequest(URL: URL)
        let identifier = self.networkActivityController?.beginNetworkActivity()
        let task = NSURLSession.sharedSession().dataTaskWithRequest(request) {
            (data, response, error) -> Void in
            self.networkActivityController?.endNetworkActivity(identifier)
            self.processData(data, response: response, error: error)
        }
        task.resume()
    }
    
    private func processData(data: NSData?, response: NSURLResponse?, error: NSError?) {
        if let data = data, response = response where response.MIMEType == "application/json" {
            var parseError: NSError?
            var jsonObject: AnyObject? = nil
            do {
                jsonObject = try NSJSONSerialization.JSONObjectWithData(data,
                    options: NSJSONReadingOptions(rawValue: 0))
            } catch let error as NSError {
                parseError = error
            }
            NSOperationQueue.mainQueue().addOperationWithBlock {
                if let parameters = jsonObject as? Parameters {
                    self.finilizeAuthorizationWithParameters(parameters)
                } else {
                    self.finilizeAuthorization(nil, error: parseError)
                }
            }
        } else {
            NSOperationQueue.mainQueue().addOperationWithBlock {
                self.finilizeAuthorization(nil, error: error)
            }
        }
    }
}
