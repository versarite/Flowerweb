unit uwebfiles;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, HTTPDefs;

procedure HandleIndexPage (Request: TRequest; Response: TResponse);
procedure HandleStaticFile(Request: TRequest; Response: TResponse);

implementation

uses
  StrUtils, uConfig;

// Reads a file byte-for-byte (safe for images, not just text).
function LoadFile(const FileName: String): String;
var
  FS : TFileStream;
begin
  Result := '';
  FS := TFileStream.Create(FileName, fmOpenRead or fmShareDenyNone);
  try
    SetLength(Result, FS.Size);
    if FS.Size > 0 then
      FS.ReadBuffer(Result[1], FS.Size);
  finally
    FS.Free;
  end;
end;

function MimeType(const FileName: String): String;
var
  Ext : String;
begin
  Ext := LowerCase(ExtractFileExt(FileName));

  if      Ext = '.html' then Result := 'text/html; charset=utf-8'
  else if Ext = '.css'  then Result := 'text/css; charset=utf-8'
  else if Ext = '.js'   then Result := 'application/javascript; charset=utf-8'
  else if Ext = '.png'  then Result := 'image/png'
  else if (Ext = '.jpg') or (Ext = '.jpeg') then Result := 'image/jpeg'
  else if Ext = '.svg'  then Result := 'image/svg+xml'
  else if Ext = '.ico'  then Result := 'image/x-icon'
  else if Ext = '.json' then Result := 'application/json'
  else Result := 'application/octet-stream';
end;

function HtmlEscape(const S: String): String;
begin
  Result := StringReplace(S,      '&', '&amp;',  [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;',   [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;',   [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
end;

procedure SendNotFound(Response: TResponse);
begin
  Response.Code := 404;
  Response.ContentType := 'text/plain';
  Response.Content := '404 - File not found';
  Response.SendContent;
end;

procedure HandleIndexPage(Request: TRequest; Response: TResponse);
var
  FileName, HTML : String;
begin
  FileName := Config.WebRoot + 'index.html';
  if not FileExists(FileName) then
  begin
    SendNotFound(Response);
    Exit;
  end;

  HTML := LoadFile(FileName);
  HTML := StringReplace(HTML, 'Config.ServerName',
                        HtmlEscape(Config.ServerName), [rfReplaceAll]);

  Response.ContentType := 'text/html; charset=utf-8';
  Response.Content := HTML;
  Response.SendContent;
end;

procedure HandleStaticFile(Request: TRequest; Response: TResponse);
var
  FileName : String;
begin
  FileName := Request.PathInfo;
  if StartsText('/', FileName) then
    Delete(FileName, 1, 1);

  // Only plain file names directly inside WebRoot.
  if (FileName = '') or (Pos('..', FileName) > 0) or
     (Pos('/', FileName) > 0) or (Pos('\', FileName) > 0) or
     (FileName[1] = '.') then
  begin
    SendNotFound(Response);
    Exit;
  end;

  FileName := Config.WebRoot + FileName;
  if not FileExists(FileName) then
  begin
    SendNotFound(Response);
    Exit;
  end;

  Response.ContentType := MimeType(FileName);
  Response.Content := LoadFile(FileName);
  Response.SendContent;
end;

end.
