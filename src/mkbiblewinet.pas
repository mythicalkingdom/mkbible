unit mkbiblewinet;
{$mode objfpc}{$H+}
{ mkbiblewinet - HTTPS downloads with the Windows Internet library (WinInet).

  Windows already has what it takes for HTTPS (the system's certificates, its TLS, the user's proxy settings), kept up to
  date by Windows Update, so the Windows build needs no OpenSSL DLLs.  The functions are declared here, so no other
  unit is needed.  Other systems use the FPC HTTP client in mkbiblerepo, and this unit only reports that it is not
  available.  (FAKEWININET compiles the Windows code on another system, with stubs for the API, to check it.) }

interface

uses
  Classes;

type
  TWinProgress = procedure(Done, Total: Int64) of object;

function WinInetGet(const Url: String; S: TStream; out Err: String; Progress: TWinProgress): Boolean;
  { the body of Url (redirects followed) into S; False and Err on a failure or an HTTP status that is not 2xx }

implementation

uses
  SysUtils{$IFDEF WINDOWS}, Windows{$ENDIF};

{$IF defined(WINDOWS) or defined(FAKEWININET)}

type
  HINTERNET = Pointer;

const
  INTERNET_OPEN_TYPE_PRECONFIG = 0;        { the user's own proxy settings }
  INTERNET_OPTION_CONNECT_TIMEOUT = 2;
  INTERNET_OPTION_SEND_TIMEOUT = 5;
  INTERNET_OPTION_RECEIVE_TIMEOUT = 6;
  INTERNET_FLAG_RELOAD = DWORD($80000000);
  INTERNET_FLAG_NO_CACHE_WRITE = $04000000;
  INTERNET_FLAG_NO_COOKIES = $00080000;
  INTERNET_FLAG_NO_UI = $00000200;
  HTTP_QUERY_CONTENT_LENGTH = 5;
  HTTP_QUERY_STATUS_CODE = 19;
  HTTP_QUERY_FLAG_NUMBER = $20000000;

{$IFDEF FAKEWININET}
{ stand-ins that only let the code below be compiled on a system without WinInet }
type
  DWORD = LongWord;
  BOOL = LongBool;
function GetLastError: DWORD; begin Result := 0; end;
function InternetOpenA(lpszAgent: PAnsiChar; dwAccessType: DWORD; lpszProxy, lpszProxyBypass: PAnsiChar; dwFlags: DWORD): HINTERNET; begin Result := nil; end;
function InternetOpenUrlA(hInternet: HINTERNET; lpszUrl, lpszHeaders: PAnsiChar; dwHeadersLength, dwFlags: DWORD; dwContext: PtrUInt): HINTERNET; begin Result := nil; end;
function InternetReadFile(hFile: HINTERNET; lpBuffer: Pointer; dwNumberOfBytesToRead: DWORD; var lpdwNumberOfBytesRead: DWORD): BOOL; begin Result := False; end;
function InternetCloseHandle(hInternet: HINTERNET): BOOL; begin Result := True; end;
function InternetSetOptionA(hInternet: HINTERNET; dwOption: DWORD; lpBuffer: Pointer; dwBufferLength: DWORD): BOOL; begin Result := True; end;
function HttpQueryInfoA(hRequest: HINTERNET; dwInfoLevel: DWORD; lpvBuffer: Pointer; var lpdwBufferLength: DWORD; lpdwIndex: PDWORD): BOOL; begin Result := False; end;
{$ELSE}
function InternetOpenA(lpszAgent: PAnsiChar; dwAccessType: DWORD; lpszProxy, lpszProxyBypass: PAnsiChar; dwFlags: DWORD): HINTERNET;
  stdcall; external 'wininet.dll' name 'InternetOpenA';
function InternetOpenUrlA(hInternet: HINTERNET; lpszUrl, lpszHeaders: PAnsiChar; dwHeadersLength, dwFlags: DWORD; dwContext: PtrUInt): HINTERNET;
  stdcall; external 'wininet.dll' name 'InternetOpenUrlA';
function InternetReadFile(hFile: HINTERNET; lpBuffer: Pointer; dwNumberOfBytesToRead: DWORD; var lpdwNumberOfBytesRead: DWORD): BOOL;
  stdcall; external 'wininet.dll' name 'InternetReadFile';
function InternetCloseHandle(hInternet: HINTERNET): BOOL;
  stdcall; external 'wininet.dll' name 'InternetCloseHandle';
function InternetSetOptionA(hInternet: HINTERNET; dwOption: DWORD; lpBuffer: Pointer; dwBufferLength: DWORD): BOOL;
  stdcall; external 'wininet.dll' name 'InternetSetOptionA';
function HttpQueryInfoA(hRequest: HINTERNET; dwInfoLevel: DWORD; lpvBuffer: Pointer; var lpdwBufferLength: DWORD; lpdwIndex: PDWORD): BOOL;
  stdcall; external 'wininet.dll' name 'HttpQueryInfoA';
{$ENDIF}

{ a WinInet error number in words (12000 and up are WinInet's own) }
function WinErr(Code: DWORD): String;
begin
  case Code of
    12002: Result := 'the server did not answer in time';
    12007: Result := 'the server could not be found (is there an internet connection?)';
    12029: Result := 'could not connect to the server';
    12030, 12031: Result := 'the connection was closed';
    12037, 12038, 12044, 12045, 12157, 12175: Result := 'could not make a secure connection (a certificate or TLS problem)';
  else
    Result := 'internet error ' + IntToStr(Code);
  end;
end;

function WinInetGet(const Url: String; S: TStream; out Err: String; Progress: TWinProgress): Boolean;
var
  Sess, Req: HINTERNET;
  Buf: array[0..65535] of Byte;
  N, Code, Len, Idx, Tmo: DWORD;
  Total, Done: Int64;
  A: AnsiString;
begin
  Result := False;
  Err := '';
  A := Url;
  Sess := InternetOpenA('mkbible', INTERNET_OPEN_TYPE_PRECONFIG, nil, nil, 0);
  if Sess = nil then begin Err := WinErr(GetLastError); Exit; end;
  try
    Tmo := 30000;
    InternetSetOptionA(Sess, INTERNET_OPTION_CONNECT_TIMEOUT, @Tmo, SizeOf(Tmo));
    InternetSetOptionA(Sess, INTERNET_OPTION_SEND_TIMEOUT, @Tmo, SizeOf(Tmo));
    InternetSetOptionA(Sess, INTERNET_OPTION_RECEIVE_TIMEOUT, @Tmo, SizeOf(Tmo));
    { redirects are followed by default; a 404 and the like still give a handle, so the status is checked below }
    Req := InternetOpenUrlA(Sess, PAnsiChar(A), nil, 0,
      INTERNET_FLAG_RELOAD or INTERNET_FLAG_NO_CACHE_WRITE or INTERNET_FLAG_NO_COOKIES or INTERNET_FLAG_NO_UI, 0);
    if Req = nil then begin Err := WinErr(GetLastError) + ' (' + Url + ')'; Exit; end;
    try
      Code := 0; Len := SizeOf(Code); Idx := 0;
      if HttpQueryInfoA(Req, HTTP_QUERY_STATUS_CODE or HTTP_QUERY_FLAG_NUMBER, @Code, Len, @Idx) then
        if (Code < 200) or (Code > 299) then
          begin Err := 'HTTP ' + IntToStr(Code) + ' for ' + Url; Exit; end;
      Total := 0;
      N := 0; Len := SizeOf(N); Idx := 0;
      if HttpQueryInfoA(Req, HTTP_QUERY_CONTENT_LENGTH or HTTP_QUERY_FLAG_NUMBER, @N, Len, @Idx) then Total := N;
      Done := 0;
      repeat
        N := 0;
        if not InternetReadFile(Req, @Buf[0], SizeOf(Buf), N) then
          begin Err := WinErr(GetLastError); Exit; end;
        if N > 0 then
          begin
          S.WriteBuffer(Buf[0], N);
          Inc(Done, N);
          if Assigned(Progress) then Progress(Done, Total);
          end;
      until N = 0;
      Result := True;
    finally
      InternetCloseHandle(Req);
    end;
  finally
    InternetCloseHandle(Sess);
  end;
end;

{$ELSE}

function WinInetGet(const Url: String; S: TStream; out Err: String; Progress: TWinProgress): Boolean;
begin
  Err := 'WinInet is only on Windows';
  Result := False;
end;

{$ENDIF}

end.
