import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:ftbase/ftbase.dart';
import 'package:http/http.dart' as http;

class HttpResponse {
  final http.Response originalResponse;

  int get statusCode => originalResponse.statusCode;
  String get body => utf8.decode(originalResponse.bodyBytes);
  String get toJson => HttpUtils.unmarshalJson(body);

  HttpResponse._private({
    required this.originalResponse,
  });
}

class HttpUtils {
  static Future<HttpResponse> getJson(
    String url, {
    Map<String, String>? headers,
    bool cached = false,
  }) async {
    return _reqJson("get", url, headers: headers, cached: cached);
  }

  static Future<HttpResponse> postJson(
    String url,
    String json, {
    Map<String, String>? headers,
    bool cached = false,
  }) async {
    return _reqJson("post", url, json: json, headers: headers, cached: cached);
  }

  static Future<HttpResponse> putJson(
    String url,
    String? json, {
    Map<String, String>? headers,
    bool cached = false,
  }) async {
    return _reqJson("put", url, json: json, headers: headers, cached: cached);
  }

  static String _hashRequest(
    String method,
    String url, {
    String? json,
    Map<String, String>? headers,
  }) {
    String reqString = "$method$url";
    if (json != null) {
      var m = unmarshalJson(json) as Map<String, dynamic>;
      var kl = m.keys as List<String>;
      kl.sort();

      for (var k in kl) {
        reqString = "$reqString$k=${m[k]}";
      }
    }

    if (headers != null) {
      var kh = headers.keys as List<String>;
      kh.sort();

      for (var k in kh) {
        reqString = "$reqString$k=${headers[k]}";
      }
    }

    List<int> b = utf8.encode(reqString);
    return sha256.convert(b).toString();
  }

  static Future<HttpResponse> _reqJson(
    String method,
    String url, {
    String? json,
    Map<String, String>? headers,
    bool cached = false,
  }) async {
    LocalStorageService ls = LocalStorageService.instance;
    headers ??= {};
    bool isUsingCache = false;

    if (!headers.containsKey("content-type")) {
      headers["content-type"] = "application/json";
    }

    int cachedStatus = 0;
    String? cachedBody;

    String reqHash = _hashRequest(method, url, headers: headers, json: json);
    String cacheKeyEtag = "httpreq-$reqHash-etag";
    String cacheKeyBody = "httpreq-$reqHash-body";
    String cacheKeyStatus = "httpreq-$reqHash-status";

    if (cached) {
      cachedBody = await ls.getString(cacheKeyBody);
      String? status = await ls.getString(cacheKeyStatus);
      if (status != null) {
        cachedStatus = int.parse(await ls.getString("httpreq-$reqHash-status") ?? "0");
      }
      String? etag = await ls.getString(cacheKeyEtag);

      if (etag != null && cachedBody != null && status != null) {
        isUsingCache = true;
        headers["If-None-Match"] = etag;
      }
    }

    http.Response response;

    if (method == "get") {
      response = await http.get(Uri.parse(url), headers: headers);
    } else {
      var f = http.post;
      if (method == "put") {
        f = http.put;
      }
      response = await f(
        Uri.parse(url),
        headers: headers,
        body: json,
      );
    }

    HttpResponse ret;
    if (isUsingCache && response.statusCode == 304) {
      response = http.Response(
        cachedBody!,
        cachedStatus,
        headers: response.headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
        request: response.request,
      );

      ret = HttpResponse._private(originalResponse: response);
    } else {
      ret = HttpResponse._private(originalResponse: response);
    }

    ls.putString(cacheKeyBody, response.body);
    ls.putString(cacheKeyStatus, "${response.statusCode}");
    if (response.headers.containsKey("etag")) {
      ls.putString(cacheKeyEtag, response.headers["etag"] ?? "");
    }

    return ret;
  }

  static String marshalJson(Object data) {
    return jsonEncode(data);
  }

  static dynamic unmarshalJson(String json) {
    return jsonDecode(json);
  }
}
