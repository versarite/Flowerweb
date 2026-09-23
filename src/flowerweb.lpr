program flowerweb;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  SysUtils, Classes, fphttpapp, httpdefs, httproute,
  uconfig, uwebfiles, uapi, ulog, uRelay;

begin
  InitializeConfiguration;

  // "flowerweb --relay-off" only closes the valve and exits.
  // systemd runs this after the service stops or crashes (ExecStopPost).
  if (ParamCount > 0) and (ParamStr(1) = '--relay-off') then
  begin
    if RelayOff then
    begin
      LogInfo('Relay forced OFF (--relay-off)');
      Halt(0);
    end
    else
      Halt(1);
  end;

  LogInfo('Executable = ' + ParamStr(0));
  LogInfo('InstallRoot = ' + Config.InstallRoot);

  InitializeRelay;

  // API routes first, then static files
  HTTPRouter.RegisterRoute('/api/status',  @HandleApiStatus);
  HTTPRouter.RegisterRoute('/api/trigger', @HandleApiTrigger);
  HTTPRouter.RegisterRoute('/api/timer',   @HandleApiTimer);
  HTTPRouter.RegisterRoute('/api/reboot',  @HandleApiReboot);

  HTTPRouter.RegisterRoute('/',          @HandleIndexPage, True);
  HTTPRouter.RegisterRoute('/:filename', @HandleStaticFile);

  Application.Port := Config.HttpPort;
  Application.Threaded := True;

  LogInfo('FlowerWeb starting on port ' + IntToStr(Config.HttpPort));

  try
    Application.Initialize;
    Application.Run;
  finally
    DoneRelay;
    LogInfo('FlowerWeb stopped');
  end;
end.
