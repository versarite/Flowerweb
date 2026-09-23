unit uconfig;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils;

const
  MIN_PULSE_MS      = 1000;     // shortest allowed valve opening
  DEFAULT_MAX_PULSE = 60000;    // hard ceiling unless the ini says otherwise
  MAX_TIMER_HOURS   = 720;      // 30 days

type
  TAppConfig = record

    // Paths (always absolute, with trailing delimiter)
    InstallRoot : String;
    WebRoot     : String;
    LogRoot     : String;
    ConfigRoot  : String;

    // HTTP Server
    HttpPort    : Integer;
    ServerName  : String;

    // Relay
    RelayPin       : Integer;
    RelayActiveLow : Boolean;   // True = relay switches ON when pin goes LOW
    Simulate       : Boolean;   // True = never touch GPIO or reboot, only log (test mode)
    RelayTimeMS    : Integer;   // valve opening time
    MaxPulseTimeMS : Integer;   // safety ceiling for RelayTimeMS

    // Automatic watering
    TimerInterval : Integer;    // hours, 0 = disabled
    NextWatering  : TDateTime;  // 0 = not scheduled

    // Camera
    CameraName  : String;
    CameraPort  : Integer;

    // Logging
    LogLevel    : String;
    LogFile     : String;
  end;

var
  Config : TAppConfig;

procedure InitializeConfiguration;
procedure SaveConfiguration;
procedure SavePulseTimeMS(const Value: Integer);
function  ClampPulseTimeMS(const Value: Integer): Integer;
function  ConfigFileName: String;

implementation

uses
  IniFiles, DateUtils, ulog;

const
  DATE_FMT = 'yyyy-mm-dd hh:nn:ss';

var
  SaveLock : TRTLCriticalSection;

function ConfigFileName: String;
begin
  Result := Config.InstallRoot + 'config/flowerweb.ini';
end;

// Relative paths in the ini are taken relative to the install directory.
function ResolvePath(const Value: String): String;
begin
  if (Value <> '') and (Value[1] = PathDelim) then
    Result := Value
  else
    Result := Config.InstallRoot + Value;
  Result := IncludeTrailingPathDelimiter(Result);
end;

function ClampPulseTimeMS(const Value: Integer): Integer;
begin
  Result := Value;
  if Result < MIN_PULSE_MS then
    Result := MIN_PULSE_MS;
  if Result > Config.MaxPulseTimeMS then
    Result := Config.MaxPulseTimeMS;
end;

function ParseDate(const S: String): TDateTime;
begin
  Result := 0;
  if Trim(S) = '' then
    Exit;
  try
    Result := ScanDateTime(DATE_FMT, Trim(S));
  except
    Result := 0;
  end;
end;

procedure InitializeConfiguration;
var
  Ini : TIniFile;
  Legacy : Integer;
begin
  // bin/flowerweb -> install root is the parent of bin/
  Config.InstallRoot := IncludeTrailingPathDelimiter(
    ExtractFileDir(ExtractFileDir(ExpandFileName(ParamStr(0)))));

  Ini := TIniFile.Create(ConfigFileName);
  try
    Config.WebRoot    := ResolvePath(Ini.ReadString('Paths', 'WebRoot',    'web'));
    Config.LogRoot    := ResolvePath(Ini.ReadString('Paths', 'LogRoot',    'logs'));
    Config.ConfigRoot := ResolvePath(Ini.ReadString('Paths', 'ConfigRoot', 'config'));

    Config.ServerName := Ini.ReadString ('Server', 'Name', 'FlowerWeb');
    Config.HttpPort   := Ini.ReadInteger('Server', 'Port', 8080);

    Config.RelayPin       := Ini.ReadInteger('Relay', 'Pin', 18);
    Config.RelayActiveLow := Ini.ReadBool   ('Relay', 'ActiveLow', False);
    Config.Simulate       := Ini.ReadBool   ('Relay', 'Simulate', False);
    Config.MaxPulseTimeMS := Ini.ReadInteger('Relay', 'MaxPulseTimeMS', DEFAULT_MAX_PULSE);
    if Config.MaxPulseTimeMS < MIN_PULSE_MS then
      Config.MaxPulseTimeMS := MIN_PULSE_MS;

    // Older ini files used the key "RelayTime"
    Legacy := Ini.ReadInteger('Relay', 'RelayTime', 5000);
    Config.RelayTimeMS := ClampPulseTimeMS(
      Ini.ReadInteger('Relay', 'PulseTimeMS', Legacy));

    Config.TimerInterval := Ini.ReadInteger('Relay', 'TimerInterval', 0);
    if (Config.TimerInterval < 0) or (Config.TimerInterval > MAX_TIMER_HOURS) then
      Config.TimerInterval := 0;
    Config.NextWatering := ParseDate(Ini.ReadString('Relay', 'NextWatering', ''));

    Config.CameraName := Ini.ReadString ('Camera', 'Name', 'cam');
    Config.CameraPort := Ini.ReadInteger('Camera', 'Port', 8889);

    Config.LogLevel := UpperCase(Ini.ReadString('Logging', 'Level', 'INFO'));
    Config.LogFile  := Ini.ReadString('Logging', 'File', 'flowerweb.log');
  finally
    Ini.Free;
  end;
end;

procedure SavePulseTimeMS(const Value: Integer);
begin
  Config.RelayTimeMS := ClampPulseTimeMS(Value);
  SaveConfiguration;
  LogInfo('Pulse time set to ' + IntToStr(Config.RelayTimeMS) + ' ms');
end;

// Only the values that can change at runtime are written back, so any
// hand-edited keys and comments in the ini stay untouched.
procedure SaveConfiguration;
var
  Ini : TIniFile;
begin
  EnterCriticalSection(SaveLock);
  try
    Ini := TIniFile.Create(ConfigFileName);
    try
      Ini.WriteInteger('Relay', 'PulseTimeMS',   Config.RelayTimeMS);
      Ini.WriteInteger('Relay', 'TimerInterval', Config.TimerInterval);
      if Config.NextWatering > 0 then
        Ini.WriteString('Relay', 'NextWatering',
                        FormatDateTime(DATE_FMT, Config.NextWatering))
      else
        Ini.WriteString('Relay', 'NextWatering', '');
      Ini.DeleteKey('Relay', 'RelayTime');   // replaced by PulseTimeMS
      Ini.UpdateFile;
    finally
      Ini.Free;
    end;
  finally
    LeaveCriticalSection(SaveLock);
  end;
end;

initialization
  InitCriticalSection(SaveLock);

finalization
  DoneCriticalSection(SaveLock);

end.
