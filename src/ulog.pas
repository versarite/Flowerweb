unit ulog;

{$mode ObjFPC}{$H+}

interface

procedure LogInfo(const Msg: String);
procedure LogError(const Msg: String);

implementation

uses
  SysUtils, uconfig;

const
  MAX_LOG_BYTES = 1024 * 1024;   // rotate to .1 when the log passes 1 MB

var
  LogLock : TRTLCriticalSection;

function LogFileName: String;
var
  Dir, Name : String;
begin
  Dir := Config.LogRoot;
  if Dir = '' then
    Dir := IncludeTrailingPathDelimiter(Config.InstallRoot) + 'logs' + PathDelim;
  Name := Config.LogFile;
  if Name = '' then
    Name := 'flowerweb.log';
  Result := IncludeTrailingPathDelimiter(Dir) + Name;
end;

procedure RotateIfNeeded(const FileName: String);
var
  Info : TSearchRec;
  Big  : Boolean;
begin
  Big := False;
  if FindFirst(FileName, faAnyFile, Info) = 0 then
  begin
    Big := Info.Size > MAX_LOG_BYTES;
    FindClose(Info);
  end;
  if Big then
  begin
    DeleteFile(FileName + '.1');
    RenameFile(FileName, FileName + '.1');
  end;
end;

procedure WriteLog(const Level, Msg: String);
var
  F    : TextFile;
  Name : String;
begin
  EnterCriticalSection(LogLock);
  try
    try
      Name := LogFileName;
      ForceDirectories(ExtractFileDir(Name));
      RotateIfNeeded(Name);

      AssignFile(F, Name);
      if FileExists(Name) then
        Append(F)
      else
        Rewrite(F);
      try
        WriteLn(F, FormatDateTime('yyyy-mm-dd hh:nn:ss', Now) +
                   ' [' + Level + '] ' + Msg);
      finally
        CloseFile(F);
      end;
    except
      // Logging must never take the server down.
    end;
  finally
    LeaveCriticalSection(LogLock);
  end;
end;

procedure LogInfo(const Msg: String);
begin
  if Config.LogLevel <> 'ERROR' then
    WriteLog('INFO', Msg);
end;

procedure LogError(const Msg: String);
begin
  WriteLog('ERROR', Msg);
end;

initialization
  InitCriticalSection(LogLock);

finalization
  DoneCriticalSection(LogLock);

end.
