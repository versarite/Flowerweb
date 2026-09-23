unit usysinfo;

{$mode ObjFPC}{$H+}

interface

uses
  Classes, SysUtils;

function GetCpuTemperature: String;
function GetLocalIPAddress: String;

Implementation
uses
  Process,
  StrUtils,ulog;

// Helper function to safely read the Pi's CPU temperature
function GetCpuTemperature: String;
var
  List: TStringList;
  RawTemp: Integer;
begin
  Result := 'Unknown';
  if FileExists('/sys/class/thermal/thermal_zone0/temp') then
  begin
    List := TStringList.Create;
    try
      List.LoadFromFile('/sys/class/thermal/thermal_zone0/temp');
      if List.Count > 0 then
      begin
        RawTemp := StrToIntDef(Trim(List.Text), 0);
        Result := FormatFloat('0.0', RawTemp / 1000) + ' °C';
      end;
    finally
      List.Free;
    end;
  end;
end;

// Helper function to grab the Pi's active local IP address
function GetLocalIPAddress: String;
var
  Proc: TProcess;
  OutputList: TStringList;
begin
  Result := '127.0.0.1';
  Proc := TProcess.Create(nil);
  OutputList := TStringList.Create;
  try
    Proc.Executable := '/usr/bin/hostname';
    Proc.Parameters.Add('-I');
    Proc.Options := [poUsePipes, poWaitOnExit];
    Proc.Execute;
    OutputList.LoadFromStream(Proc.Output);
    if OutputList.Count > 0 then
      Result := Trim(ExtractWord(1, OutputList.Text, [' ']));
  finally
    OutputList.Free;
    Proc.Free;
  end;
end;
end.