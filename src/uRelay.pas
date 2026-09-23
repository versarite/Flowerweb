unit uRelay;

{$mode ObjFPC}{$H+}

// Relay / valve control.
//
// One background thread (TRelayThread) owns all timing:
//   * it switches the valve OFF when the current watering run is over
//   * it starts automatic watering when the timer is due
// HTTP requests never sleep; StartWatering switches the valve ON and returns
// immediately. All shared state is protected by RelayLock.
//
// Safety: the valve is forced OFF at startup, at shutdown, when a watering
// run ends (also on errors), and by "flowerweb --relay-off", which the
// systemd unit runs after the service stops or crashes.

interface

uses
  Classes, SysUtils;

type
  TWaterResult = (wrStarted, wrBusy, wrGpioError);

  TRelayThread = class(TThread)
  protected
    procedure Execute; override;
  end;

procedure InitializeRelay;
procedure DoneRelay;
function  RelayOff: Boolean;
procedure SetTimerInterval(const Hours: Integer);
function  StartWatering: TWaterResult;
function  IsWatering: Boolean;
function  WateringSecondsLeft: Integer;
function  TimerEnabled: Boolean;
function  MinutesRemaining: Integer;

implementation

uses
  Process, DateUtils, uLog, uConfig;

const
  POLL_MS = 250;

var
  RelayLock      : TRTLCriticalSection;
  RelayThread    : TRelayThread = nil;
  WateringActive : Boolean = False;
  WateringUntil  : TDateTime = 0;

// ------------------------------------------------------------------
// GPIO
// ------------------------------------------------------------------

function GpioTool: String;
begin
  if FileExists('/usr/bin/pinctrl') then
    Result := '/usr/bin/pinctrl'
  else
    Result := '/usr/bin/raspi-gpio';
end;

// Drives the relay pin. RelayOn=True means "valve open", independent of
// whether the relay board is active-high or active-low.
function SetRelay(const RelayOn: Boolean): Boolean;
var
  Proc  : TProcess;
  PinHigh : Boolean;
begin
  Result := False;
  PinHigh := RelayOn xor Config.RelayActiveLow;

  if Config.Simulate then
  begin
    LogInfo('[SIMULATE] GPIO ' + IntToStr(Config.RelayPin) + ' would be set ' +
            BoolToStr(PinHigh, 'high', 'low') + ' (valve ' + BoolToStr(RelayOn, 'OPEN', 'CLOSED') + ')');
    Exit(True);
  end;

  Proc := TProcess.Create(nil);
  try
    try
      Proc.Executable := GpioTool;
      Proc.Options := [poWaitOnExit];
      Proc.Parameters.Add('set');
      Proc.Parameters.Add(IntToStr(Config.RelayPin));
      Proc.Parameters.Add('op');
      if PinHigh then
        Proc.Parameters.Add('dh')
      else
        Proc.Parameters.Add('dl');
      Proc.Execute;
      Result := (Proc.ExitStatus = 0);
    except
      on E: Exception do
        LogError('GPIO command failed: ' + E.Message);
    end;
  finally
    Proc.Free;
  end;

  if not Result then
    LogError('GPIO ' + IntToStr(Config.RelayPin) + ' could not be set ' +
             BoolToStr(RelayOn, 'ON', 'OFF'));
end;

function RelayOff: Boolean;
begin
  Result := SetRelay(False);
end;

// ------------------------------------------------------------------
// Watering
// ------------------------------------------------------------------

function StartWatering: TWaterResult;
begin
  EnterCriticalSection(RelayLock);
  try
    if WateringActive then
      Exit(wrBusy);

    LogInfo('Watering for ' + IntToStr(Config.RelayTimeMS div 1000) + ' s');

    if not SetRelay(True) then
    begin
      RelayOff;   // make sure it is not left half-on
      Exit(wrGpioError);
    end;

    WateringActive := True;
    WateringUntil  := IncMilliSecond(Now, Config.RelayTimeMS);
    Result := wrStarted;
  finally
    LeaveCriticalSection(RelayLock);
  end;
end;

procedure StopWateringIfDue;
begin
  EnterCriticalSection(RelayLock);
  try
    if WateringActive and (Now >= WateringUntil) then
    begin
      WateringActive := False;
      if RelayOff then
        LogInfo('Watering finished')
      else
        LogError('Watering finished but relay OFF failed!');
    end;
  finally
    LeaveCriticalSection(RelayLock);
  end;
end;

function IsWatering: Boolean;
begin
  EnterCriticalSection(RelayLock);
  try
    Result := WateringActive;
  finally
    LeaveCriticalSection(RelayLock);
  end;
end;

function WateringSecondsLeft: Integer;
begin
  EnterCriticalSection(RelayLock);
  try
    if WateringActive then
      Result := SecondsBetween(WateringUntil, Now)
    else
      Result := 0;
  finally
    LeaveCriticalSection(RelayLock);
  end;
end;

// ------------------------------------------------------------------
// Automatic timer
// ------------------------------------------------------------------

procedure SetTimerInterval(const Hours: Integer);
begin
  EnterCriticalSection(RelayLock);
  try
    if Hours <= 0 then
    begin
      Config.TimerInterval := 0;
      Config.NextWatering  := 0;
      LogInfo('Water timer disabled');
    end
    else
    begin
      Config.TimerInterval := Hours;
      Config.NextWatering  := IncHour(Now, Hours);
      LogInfo('Water timer enabled (' + IntToStr(Hours) + ' h), next at ' +
              FormatDateTime('yyyy-mm-dd hh:nn', Config.NextWatering));
    end;
  finally
    LeaveCriticalSection(RelayLock);
  end;
  SaveConfiguration;
end;

procedure CheckTimer;
var
  Due : Boolean;
begin
  EnterCriticalSection(RelayLock);
  try
    Due := (Config.TimerInterval > 0) and (Config.NextWatering > 0) and
           (Now >= Config.NextWatering);
    if Due then
      Config.NextWatering := IncHour(Now, Config.TimerInterval);
  finally
    LeaveCriticalSection(RelayLock);
  end;

  if Due then
  begin
    LogInfo('Automatic watering');
    SaveConfiguration;   // persist the next due time
    if StartWatering = wrBusy then
      LogInfo('Automatic watering skipped: already watering');
  end;
end;

function TimerEnabled: Boolean;
begin
  Result := Config.TimerInterval > 0;
end;

function MinutesRemaining: Integer;
begin
  EnterCriticalSection(RelayLock);
  try
    if (Config.TimerInterval <= 0) or (Config.NextWatering <= 0) then
      Exit(0);
    Result := Trunc((Config.NextWatering - Now) * 24 * 60);
    if Result < 0 then
      Result := 0;
  finally
    LeaveCriticalSection(RelayLock);
  end;
end;

// ------------------------------------------------------------------
// Thread
// ------------------------------------------------------------------

procedure TRelayThread.Execute;
begin
  while not Terminated do
  begin
    try
      StopWateringIfDue;
      CheckTimer;
    except
      on E: Exception do
        LogError('Relay thread: ' + E.Message);
    end;
    Sleep(POLL_MS);
  end;
end;

procedure InitializeRelay;
begin
  // Valve closed, whatever state a previous run left it in.
  RelayOff;

  if Config.TimerInterval > 0 then
  begin
    if Config.NextWatering <= 0 then
      Config.NextWatering := IncHour(Now, Config.TimerInterval);
    if Config.NextWatering <= Now then
      LogInfo('Water timer: a watering was missed while offline, running it now')
    else
      LogInfo('Water timer restored (' + IntToStr(Config.TimerInterval) +
              ' h), next at ' +
              FormatDateTime('yyyy-mm-dd hh:nn', Config.NextWatering));
  end;

  RelayThread := TRelayThread.Create(False);
end;

procedure DoneRelay;
begin
  if Assigned(RelayThread) then
  begin
    RelayThread.Terminate;
    RelayThread.WaitFor;
    FreeAndNil(RelayThread);
  end;
  RelayOff;
end;

initialization
  InitCriticalSection(RelayLock);

finalization
  DoneCriticalSection(RelayLock);

end.
