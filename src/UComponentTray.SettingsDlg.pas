unit UComponentTray.SettingsDlg;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls, Vcl.ExtCtrls;

type
  TSettingsDlg = class(TForm)
    Button1: TButton;
    Button2: TButton;
    rgStyle: TRadioGroup;
    rgPosition: TRadioGroup;
    GroupBox1: TGroupBox;
    cbSplitterEnabled: TCheckBox;
    cbSplitterColor: TColorBox;
  private
    { Private 宣言 }
  public
    { Public 宣言 }
  end;

function ShowSettingsDlg(var Style, Position: Integer;
  var SplitterEnabled: Boolean; var SplitterColor: TColor): Boolean;

implementation

{$R *.dfm}

function ShowSettingsDlg(var Style, Position: Integer;
  var SplitterEnabled: Boolean; var SplitterColor: TColor): Boolean;
var
  dlg: TSettingsDlg;
begin
  dlg := TSettingsDlg.Create(nil);
  try
    dlg.rgStyle.ItemIndex := Style;
    dlg.rgPosition.ItemIndex := Position;
    dlg.cbSplitterEnabled.Checked := SplitterEnabled;
    dlg.cbSplitterColor.Selected := SplitterColor;

    Result := dlg.ShowModal = mrOk;
    if not Result then Exit;

    Style := dlg.rgStyle.ItemIndex;
    Position := dlg.rgPosition.ItemIndex;
    SplitterEnabled := dlg.cbSplitterEnabled.Checked;
    SplitterColor := dlg.cbSplitterColor.Selected;
  finally
    dlg.Free;
  end;
end;

end.
