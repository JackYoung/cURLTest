//
//  TestCURLTests.swift
//  TestCURLTests
//
//  Created by mato on 16/3/3.
//  Copyright © 2016年 JackYoung. All rights reserved.
//

import XCTest
import MobileCoreServices
@testable import TestCURL

class TestCURLTests: XCTestCase {
  
  var crls = [cURL]()
  
  override func setUp() {
    super.setUp()
  }
  
  override func tearDown() {
    super.tearDown()
  }
  
  func testGet() {
    let crl: cURL = cURL(url: "http://httpbin.org/get?key2=value2&key1=value1")
    let crlResults = crl.performFully()
    XCTAssert(crlResults.0 == 0)
    if let headerString: String = String.fromCString(UnsafePointer(crlResults.1)) {
      NSLog("\r\nResponse Headers : \r\n%@", headerString)
    }
    NSLog("timeline : \(crlResults.3)")
    
    var json: [String: AnyObject]!
    do {
      let data = NSData.init(bytes: UnsafePointer(crlResults.2), length: crlResults.2.count)
      if let responseBody = String(data: data, encoding: NSUTF8StringEncoding) {
        NSLog("response data %@", responseBody)
      }
      
      json = try NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions()) as! [String : AnyObject]
    } catch {
      XCTAssert(false)
    }
    
    guard let args = json["args"] as? [String: String],
      let value1 = args["key1"],
      let value2 = args["key2"] else {
        XCTAssert(false)
        return
    }
    
    XCTAssert((value1 == "value1") && (value2 == "value2"))
  }
  
  func testPost() {
    let postString = "custname=custom_name&custtel=tel&custemail=addr%40gmail.com&size=medium&topping=cheese&delivery=&comments=123"
    let crl: cURL = cURL(url: "http://httpbin.org/post")
    let postData = postString.dataUsingEncoding(NSUTF8StringEncoding)
    crl.setRequestBody(postData!, contentType: "application/x-www-form-urlencoded", contentLength: UInt64(postData!.length))
    crl.setHeader("X-Forwarded-From", value: "127.0.0.1")
    crl.setVerb("POST")
    let crlResults = crl.performFully()
    XCTAssert(crlResults.0 == 0)
    if let headerString: String = String.fromCString(UnsafePointer(crlResults.1)) {
      NSLog("\r\nResponse Headers : \r\n%@", headerString)
    }
    NSLog("timeline : \(crlResults.3)")
    
    var json: [String: AnyObject]!
    do {
      let data = NSData.init(bytes: UnsafePointer(crlResults.2), length: crlResults.2.count)
      if let responseBody = String(data: data, encoding: NSUTF8StringEncoding) {
        NSLog("response data %@", responseBody)
      }
      json = try NSJSONSerialization.JSONObjectWithData(data, options: NSJSONReadingOptions()) as! [String : AnyObject]
    } catch {
      XCTAssert(false)
    }
    
    NSLog("\r\nResponse Body : \r\n%@", json)
    guard let form = json["form"] as? [String: String]
      else {
        XCTAssert(false)
        return
    }
    
    guard let headers = json["headers"] as? [String: String]
      else {
        XCTAssert(false)
        return
    }
    
    XCTAssert(form["custtel"] == "tel")
    XCTAssert(form["custname"] == "custom_name")
    
    XCTAssert(headers["X-Forwarded-From"] == "127.0.0.1")
  }
  
  func testPut() {
    let bundle = NSBundle(forClass: self.dynamicType)
    guard let dataPath = bundle.pathForResource("put", ofType: "gif")
      else {
        XCTAssert(false)
        return
    }
    
    var fileSize: UInt64 = 0
    do {
      if let fileAttr: NSDictionary = try NSFileManager.defaultManager().attributesOfItemAtPath(dataPath) as NSDictionary {
        fileSize = fileAttr.fileSize()
      }
    } catch {
      XCTAssert(false)
    }
    
    let gifInput = NSInputStream(fileAtPath: dataPath)
    let crl: cURL = cURL(url: "http://httpbin.org/put")
    let mimeType = self.mimeTypeOf(dataPath)
    crl.setVerb("PUT")
    crl.setRequestStream(gifInput!, contentType: mimeType, contentLength: fileSize)
    let crlResults = crl.performFully()
    NSLog("timeline : \(crlResults.3)")
    
    XCTAssert(crlResults.0 == 0)
    if let headerString: String = String.fromCString(UnsafePointer(crlResults.1)) {
      NSLog("\r\nResponse Headers : \r\n%@", headerString)
    }
    
    let data = NSData.init(bytes: UnsafePointer(crlResults.2), length: crlResults.2.count)
    if let responseBody = String(data: data, encoding: NSUTF8StringEncoding) {
      NSLog("response data %@", responseBody)
    }
    
    XCTAssert(crl.responseCode == 200)
  }
  
  func testRedirect() {
    let crl: cURL = cURL(url: "http://httpbin.org/relative-redirect/1")
    let crlResults = crl.performFully()
    
    XCTAssert(crlResults.0 == 0)
    if let headerString: String = String.fromCString(UnsafePointer(crlResults.1)) {
      NSLog("\r\nResponse Headers : \r\n%@", headerString)
    }
    
    XCTAssert(crl.responseCode == 302)
  }

  // Run and capture packets
  func testKeepAlive() {
    let crl = cURL(url: "http://httpbin.org/get?key2=value2&key1=value1")
    for _ in 1...5 {
      crl.url = "http://httpbin.org/get?key2=value2&key1=value1"
      let crlResults = crl.performFully()
      XCTAssert(crlResults.0 == 0)
      if let headerString: String = String.fromCString(UnsafePointer(crlResults.1)) {
        NSLog("\r\nResponse Headers : \r\n%@", headerString)
      }
    }
  }
  
  func mimeTypeOf(filePath: String) -> String {
    let ext = NSString(string: filePath).pathExtension
    
    guard let UTI = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, ext as CFString, nil)?.takeRetainedValue()
      else {
        return "application/octet-stream"
    }
    
    guard let registedType = UTTypeCopyPreferredTagWithClass(UTI, kUTTagClassMIMEType)?.takeRetainedValue()
      else {
        return "application/octet-stream"
    }
    
    return registedType as String
  }
  
  func testPerformanceExample() {
    // This is an example of a performance test case.
    self.measureBlock {
      // Put the code you want to measure the time of here.
    }
  }
  
}
