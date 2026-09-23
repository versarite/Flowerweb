unit uapi;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils, HTTPDefs;

procedure HandleApiStatus (Request: TRequest; Response: TResponse);
procedure HandleApiTrigger(Request: TRequest; Response: TResponse);
procedure HandleApiReboot (Request: TRequest; Response: TResponse);
procedure HandleApiTimer  (Request: TRequest; Response: TResponse);

implementation

uses
  Process, fpjson, jsonparser,
  uconfig, usysinfo, ulog, urelay;

// ------------------------------------------------------------------
// Helpers
// ------------------------------------------------------------------

procedure SendJSON(Response: TResponse; Code: Integer; Obj: TJSONObject);
begin
  try
    Response.Code := Code;
    Response.ContentType := 'application/json';
    Response.Content := Obj.AsJSON;
    Response.SendContent;
  finally
    Obj.Free;
  end;
end;

procedure SendError(Response: TResponse; Code: Integer; const Msg: String);
begin
  SendJSON(Response, Code,
    TJSONObject.Create(['status', 'error', 'message', Msg]));
end;

function RequirePost(Request: TRequest; Response: TResponse): Boolean;
begin
  Result := SameText(Request.Method, 'POST');
  if not Result then
    SendError(Response, 405, 'Use POST');
end;

// Returns the request body as a JSON object, or nil if the body is empty.
// Raises EJSON / EConvertError on malformed input.
function ParseBody(Request: TRequest): TJSONObject;
var
  Data : TJSONData;
begin
  Result := nil;
  if Trim(Request.Content) = '' then
    Exit;
  Data := GetJSON(Request.Content);
  if Data is TJSONObject then
    Result := TJSONObject(Data)
  else
  begin
    Data.Free;
    raise EJSON.Create('JSON object expected');
  end;
end;

// ------------------------------------------------------------------
// GET /api/status
// ------------------------------------------------------------------

procedure HandleApiStatus(Request: TRequest; Response: TResponse);
var
  Obj : TJSONObject;
begin
  Obj := TJSONObject.Create;
  Obj.Add('server',           Config.ServerName);
  Obj.Add('temp',             GetCpuTemperature);
  Obj.Add('ip',               GetLocalIPAddress);
  Obj.Add('pulseTimeMS',      Config.RelayTimeMS);
  Obj.Add('maxPulseTimeMS',   Config.MaxPulseTimeMS);
  Obj.Add('timerInterval',    Config.TimerInterval);
  Obj.Add('minutesRemaining', MinutesRemaining);
  Obj.Add('hoursRemaining',   MinutesRemaining div 60);   // kept for old clients
  Obj.Add('watering',         IsWatering);
  Obj.Add('wateringSecondsLeft', WateringSecondsLeft);
  Obj.Add('cameraName',       Config.CameraName);
  Obj.Add('cameraPort',       Config.CameraPort);
  SendJSON(Response, 200, Obj);
end;

// ------------------------------------------------------------------
// POST /api/trigger   body (optional): {"pulseTimeMS": 5000}
// ------------------------------------------------------------------

procedure HandleApiTrigger(Request: TRequest; Response: TResponse);
var
  Body  : TJSONObject;
  Pulse : Integer;
begin
  if not RequirePost(Request, Response) then
    Exit;

  try
    Body := ParseBody(Request);
  except
    on E: Exception do
    begin
      SendError(Response, 400, 'Invalid JSON');
      Exit;
    end;
  end;

  try
    if Assigned(Body) and (Body.IndexOfName('pulseTimeMS') >= 0) then
    begin
      Pulse := Body.Get('pulseTimeMS', Config.RelayTimeMS);
      if IsWatering then
      begin
        SendError(Response, 409, 'Already watering');
        Exit;
      end;
      if Pulse <> Config.RelayTimeMS then
        SavePulseTimeMS(Pulse);   // clamped to MIN..MaxPulseTimeMS
    end;
  finally
    Body.Free;
  end;

  LogInfo('Manual watering requested by ' + Request.RemoteAddr);

  case StartWatering of
    wrStarted:
      SendJSON(Response, 200, TJSONObject.Create([
        'status', 'success',
        'pulseTimeMS', Config.RelayTimeMS]));
    wrBusy:
      SendError(Response, 409, 'Already watering');
  else
    SendError(Response, 500, 'GPIO command failed');
  end;
end;

// ------------------------------------------------------------------
// POST /api/timer   body: {"timerInterval": 24}
// ------------------------------------------------------------------

procedure HandleApiTimer(Request: TRequest; Response: TResponse);
var
  Body  : TJSONObject;
  Hours : Integer;
begin
  if not RequirePost(Request, Response) then
    Exit;

  try
    Body := ParseBody(Request);
  except
    on E: Exception do
    begin
      SendError(Response, 400, 'Invalid JSON');
      Exit;
    end;
  end;

  try
    if not Assigned(Body) or (Body.IndexOfName('timerInterval') < 0) then
    begin
      SendError(Response, 400, 'timerInterval missing');
      Exit;
    end;
    Hours := Body.Get('timerInterval', 0);
  finally
    Body.Free;
  end;

  if (Hours < 0) or (Hours > MAX_TIMER_HOURS) then
  begin
    SendError(Response, 400, 'timerInterval must be 0..' + IntToStr(MAX_TIMER_HOURS));
    Exit;
  end;

  SetTimerInterval(Hours);   // also saves the configuration

  SendJSON(Response, 200, TJSONObject.Create([
    'status', 'success',
    'timerInterval', Config.TimerInterval,
    'minutesRemaining', MinutesRemaining]));
end;

// ------------------------------------------------------------------
// POST /api/reboot
// ------------------------------------------------------------------

procedure HandleApiReboot(Request: TRequest; Response: TResponse);
var
  Proc : TProcess;
begin
  if not RequirePost(Request, Response) then
    Exit;

  LogInfo('Reboot requested by ' + Request.RemoteAddr);
  RelayOff;

  SendJSON(Response, 200, TJSONObject.Create(['status', 'rebooting']));

  Proc := TProcess.Create(nil);
  try
    try
      Proc.Executable := '/usr/bin/sudo';
      Proc.Parameters.Add('/usr/sbin/reboot');
      Proc.Execute;
    except
      on E: Exception do
        LogError('Reboot failed: ' + E.Message);
    end;
  finally
    Proc.Free;
  end;
end;

end.
