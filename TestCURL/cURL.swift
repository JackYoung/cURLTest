//
//  cURL.swift
//  PerfectLib
//
//  Created by Kyle Jessup on 2015-08-10.
//	Copyright (C) 2015 PerfectlySoft, Inc.
//
//	This program is free software: you can redistribute it and/or modify
//	it under the terms of the GNU Affero General Public License as
//	published by the Free Software Foundation, either version 3 of the
//	License, or (at your option) any later version, as supplemented by the
//	Perfect Additional Terms.
//
//	This program is distributed in the hope that it will be useful,
//	but WITHOUT ANY WARRANTY; without even the implied warranty of
//	MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//	GNU Affero General Public License, as supplemented by the
//	Perfect Additional Terms, for more details.
//
//	You should have received a copy of the GNU Affero General Public License
//	and the Perfect Additional Terms that immediately follow the terms and
//	conditions of the GNU Affero General Public License along with this
//	program. If not, see <http://www.perfect.org/AGPL_3_0_With_Perfect_Additional_Terms.txt>.
//

import UIKit
import cURL

public struct Timeline {
  var totalCost: Int
  var dnsCost: Int
  var connectCost: Int
  var uploadCost: Int
  var downloadCost: Int
  var waitingCost: Int
}

private struct BodyStreamWrapper {
  var input: NSInputStream
  var contentType: String
  var contentLength: UInt64
}

public class cURL: NSObject {
  
  /// This class is a wrapper around the CURL library. It permits network operations to be completed using cURL in a block or non-blocking manner.
  
  static var sInit:Int = {
    curl_global_init(Int(CURL_GLOBAL_SSL | CURL_GLOBAL_WIN32))
    return 1
  }()
  
  var curl: UnsafeMutablePointer<Void>?
  var requestHeadersDict = [String: String]()
  var slists = [UnsafeMutablePointer<curl_slist>]()
  var headerBytes = [UInt8]()
  var bodyBytes = [UInt8]()
  
  private var requestBodyStream: BodyStreamWrapper?
  
  /// The CURLINFO_RESPONSE_CODE for the last operation.
  public  var responseCode: Int {
    return self.getInfo(CURLINFO_RESPONSE_CODE).0
  }
  
  /// Get or set the current URL.
  public var url: String {
    get {
      return self.getInfo(CURLINFO_EFFECTIVE_URL).0
    }
    set {
      self.setOption(CURLOPT_URL, s: newValue)
    }
  }
  
  /// Initialize the CURL request.
  public override init() {
    super.init()
    self.curl = curl_easy_init()
  }
  
  /// Initialize the CURL request with a given URL.
  public convenience init(url: String) {
    self.init()
    self.url = url
  }
  
  /// Duplicate the given request into a new CURL object.
  public init(dupeCurl: cURL) {
    super.init()
    if let copyFrom = dupeCurl.curl {
      self.curl = curl_easy_duphandle(copyFrom)
    } else {
      self.curl = curl_easy_init()
    }
    setCurlOpts() // still set options
  }
  
  public func setCurlOpts() {
    let opaqueMe = UnsafeMutablePointer<Void>(Unmanaged.passUnretained(self).toOpaque())
    
    setOption(CURLOPT_NOSIGNAL, int: 1)
    setOption(CURLOPT_HEADERDATA, v: opaqueMe)
    setOption(CURLOPT_WRITEDATA, v: opaqueMe)
    setOption(CURLOPT_EXPECT_100_TIMEOUT_MS, int: 0)
    setOption(CURLOPT_VERBOSE, int: 1)
    
    let headerReadFunc: curl_func = {
      (a: UnsafeMutablePointer<Void>, size: Int, num: Int, p: UnsafeMutablePointer<Void>) -> Int in
      
      let crl = Unmanaged<cURL>.fromOpaque(COpaquePointer(p)).takeUnretainedValue()
      let bytes = UnsafeMutablePointer<UInt8>(a)
      let fullCount = size*num
      for idx in 0..<fullCount {
        crl.headerBytes.append(bytes[idx])
      }
      return fullCount
    }
    setOption(CURLOPT_HEADERFUNCTION, f: headerReadFunc)
    
    let writeFunc: curl_func = {
      (a: UnsafeMutablePointer<Void>, size: Int, num: Int, p: UnsafeMutablePointer<Void>) -> Int in
      
      let crl = Unmanaged<cURL>.fromOpaque(COpaquePointer(p)).takeUnretainedValue()
      let bytes = UnsafeMutablePointer<UInt8>(a)
      let fullCount = size*num
      for idx in 0..<fullCount {
        crl.bodyBytes.append(bytes[idx])
      }
      return fullCount
    }
    setOption(CURLOPT_WRITEFUNCTION, f: writeFunc)
    
    let readFunc: curl_func = {
      (buffPtr: UnsafeMutablePointer<Void>, size: Int, num: Int, p: UnsafeMutablePointer<Void>) -> Int in
      var readNum = 0
      let crl = Unmanaged<cURL>.fromOpaque(COpaquePointer(p)).takeUnretainedValue()
      if let requestBodyStream = crl.requestBodyStream {
        requestBodyStream.input.open();
        readNum = requestBodyStream.input.read(UnsafeMutablePointer<UInt8>(buffPtr), maxLength: num)
        if readNum < num {
          requestBodyStream.input.close()
        }
      }
      return readNum
    }
    
    let nullReadFunc: curl_func = {
      (buffPtr: UnsafeMutablePointer<Void>, size: Int, num: Int, p: UnsafeMutablePointer<Void>) -> Int in
      return -1
    }
    
    if let postBodyStream = self.requestBodyStream {
      setOption(CURLOPT_UPLOAD, int: 1)
      setOption(CURLOPT_INFILESIZE, int64: Int64(postBodyStream.contentLength))
      setOption(CURLOPT_READDATA, v: opaqueMe)
      setOption(CURLOPT_READFUNCTION, f: readFunc)
      setHeader("Content-Type", value: postBodyStream.contentType)
    } else {
      setOption(CURLOPT_HTTPGET, int: 1)
      setOption(CURLOPT_UPLOAD, int: 0)
      setOption(CURLOPT_INFILESIZE, int64: 0)
      setOption(CURLOPT_READDATA, v: UnsafeMutablePointer<Void>())
      setOption(CURLOPT_READFUNCTION, f: nullReadFunc)
    }
    
  }
  
  /// Clean up and reset the CURL object.
  public func reset() {
    if self.curl != nil {
      while self.slists.count > 0 {
        curl_slist_free_all(self.slists.last!)
        self.slists.removeLast()
      }
      self.requestHeadersDict.removeAll()
      self.requestBodyStream = nil
      curl_easy_reset(self.curl!)
    }
  }
  
  /// Performs the request, blocking the current thread until it completes.
  /// - returns: A tuple consisting of: Int - the result code, [UInt8] - the header bytes if any, [UInt8] - the body bytes if any
  public func performFully() -> (Int, [UInt8], [UInt8], Timeline) {
    self.setCurlOpts()
    
    var slists: UnsafeMutablePointer<curl_slist> = UnsafeMutablePointer<curl_slist>()
    for (key, value) in self.requestHeadersDict {
      slists = curl_slist_append(slists, "\(key): \(value)")
    }
    slists = curl_slist_append(slists, "Expect: ")
    setOption(CURLOPT_HTTPHEADER, slists: slists)
    
    let code = curl_easy_perform(self.curl!)
    defer {
      if self.headerBytes.count > 0 {
        self.headerBytes = [UInt8]()
      }
      if self.bodyBytes.count > 0 {
        self.bodyBytes = [UInt8]()
      }
      curl_slist_free_all(slists)
      self.reset()
    }
    if code != CURLE_OK {
      let str = self.strError(code)
      print(str)
    }
    return (Int(code.rawValue), self.headerBytes, self.bodyBytes, timeline())
  }
  
  /// Returns the String message for the given CURL result code.
  public func strError(code: CURLcode) -> String {
    return String.fromCString(curl_easy_strerror(code))!
  }
  
  public func getConnectionNums() -> Int {
    return getInfo(CURLINFO_NUM_CONNECTS).0
  }
  
  public func timeline() -> Timeline {
    let totalTime = Int(getDoubleInfo(CURLINFO_TOTAL_TIME).0 * 1000)
    let dnsTime = Int(getDoubleInfo(CURLINFO_NAMELOOKUP_TIME).0 * 1000)
    let connectTime = Int(getDoubleInfo(CURLINFO_CONNECT_TIME).0 * 1000)
    let pretransferTime = Int(getDoubleInfo(CURLINFO_PRETRANSFER_TIME).0 * 1000)
    let startTransferTime = Int(getDoubleInfo(CURLINFO_STARTTRANSFER_TIME).0 * 1000)
    
    let dnsCost: Int = dnsTime > 0 ? dnsTime : 0
    let connectCost: Int = (connectTime - dnsTime) > 0 ? (connectTime - dnsTime) : 0
    let sendCost: Int = (pretransferTime - connectTime) > 0 ? (pretransferTime - connectTime) : 0
    let waitCost: Int = (startTransferTime - pretransferTime) > 0 ? (startTransferTime - pretransferTime) : 0
    let receiveCost: Int = (totalTime - startTransferTime) > 0 ? (totalTime - startTransferTime) : 0
    
    return Timeline(totalCost: totalTime, dnsCost: dnsCost, connectCost: connectCost, uploadCost: sendCost, downloadCost: receiveCost, waitingCost: waitCost)
  }
  
  /// Returns the Int value for the given CURLINFO.
  public func getInfo(info: CURLINFO) -> (Int, CURLcode) {
    var i = 0
    let c = curl_easy_getinfo_long(self.curl!, info, &i)
    return (i, c)
  }
  
  public func getDoubleInfo(info: CURLINFO) -> (Double, CURLcode) {
    var i: Double = 0.0
    let c = curl_easy_getinfo_double(self.curl!, info, &i)
    return (i, c)
  }
  
  /// Returns the String value for the given CURLINFO.
  public func getInfo(info: CURLINFO) -> (String, CURLcode) {
    let i = UnsafeMutablePointer<UnsafePointer<Int8>>.alloc(1)
    defer { i.destroy(); i.dealloc(1) }
    let code = curl_easy_getinfo_cstr(self.curl!, info, i)
    return (code != CURLE_OK ? "" : String.fromCString(i.memory)!, code)
  }
  
  /// Sets the Int64 option value.
  public func setOption(option: CURLoption, int64: Int64) -> CURLcode {
    return curl_easy_setopt_int64(self.curl!, option, int64)
  }
  
  /// Sets the Int option value.
  public func setOption(option: CURLoption, int: Int) -> CURLcode {
    return curl_easy_setopt_long(self.curl!, option, int)
  }
  
  /// Sets the poionter option value.
  public func setOption(option: CURLoption, v: UnsafeMutablePointer<Void>) -> CURLcode {
    return curl_easy_setopt_void(self.curl!, option, v)
  }
  
  /// Sets the callback function option value.
  public func setOption(option: CURLoption, f: curl_func) -> CURLcode {
    return curl_easy_setopt_func(self.curl!, option, f)
  }
  
  public func setOption(option: CURLoption, slists: UnsafeMutablePointer<curl_slist>) -> CURLcode {
    return curl_easy_setopt_slist(self.curl!, option, slists)
  }
  
  /// Sets the String option value.
  public func setOption(option: CURLoption, s: String) -> CURLcode {
    switch(option.rawValue) {
    case CURLOPT_HTTP200ALIASES.rawValue,
    CURLOPT_POSTQUOTE.rawValue,
    CURLOPT_PREQUOTE.rawValue,
    CURLOPT_QUOTE.rawValue,
    CURLOPT_MAIL_FROM.rawValue,
    CURLOPT_MAIL_RCPT.rawValue:
      let slist = curl_slist_append(nil, s)
      self.slists.append(slist)
      return curl_easy_setopt_slist(self.curl!, option, slist)
    default:
      ()
    }
    return curl_easy_setopt_cstr(self.curl!, option, s)
  }
  
  public func setHeader(key: String, value: String) {
    self.requestHeadersDict[key] = value
  }
  
  public func setVerb(verb: String) {
    self.setOption(CURLOPT_CUSTOMREQUEST, s: verb)
  }
  
  public func setRequestBody(data: NSData, contentType: String, contentLength: UInt64) {
    let bodyInput = NSInputStream.init(data: data)
    setRequestStream(bodyInput, contentType: contentType, contentLength: contentLength)
  }

  public func setRequestStream(dataStream: NSInputStream, contentType: String, contentLength: UInt64) {
    self.requestBodyStream = BodyStreamWrapper(input: dataStream, contentType: contentType, contentLength: contentLength)
  }
  
  /// Cleanup and close the CURL request.
  public func close() {
    if self.curl != nil {
      curl_easy_cleanup(self.curl!)
      
      self.requestBodyStream = nil
      self.requestHeadersDict.removeAll()
      self.curl = nil
      while self.slists.count > 0 {
        curl_slist_free_all(self.slists.last!)
        self.slists.removeLast()
      }
    }
  }
  
  deinit {
    self.close()
  }
  
}
