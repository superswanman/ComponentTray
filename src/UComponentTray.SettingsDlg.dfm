object SettingsDlg: TSettingsDlg
  Left = 0
  Top = 0
  BorderIcons = []
  BorderStyle = bsDialog
  Caption = 'Settings'
  ClientHeight = 219
  ClientWidth = 253
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'MS UI Gothic'
  Font.Style = []
  OldCreateOrder = False
  Position = poMainFormCenter
  Scaled = False
  DesignSize = (
    253
    219)
  PixelsPerInch = 96
  TextHeight = 12
  object Button1: TButton
    Left = 89
    Top = 186
    Width = 75
    Height = 25
    Anchors = [akRight, akBottom]
    Caption = 'OK'
    ModalResult = 1
    TabOrder = 0
  end
  object Button2: TButton
    Left = 170
    Top = 186
    Width = 75
    Height = 25
    Anchors = [akRight, akBottom]
    Caption = 'Cancel'
    ModalResult = 2
    TabOrder = 1
  end
  object rgStyle: TRadioGroup
    Left = 8
    Top = 8
    Width = 237
    Height = 53
    Caption = 'Style'
    Columns = 3
    Items.Strings = (
      'Icon'
      'Tile'
      'List')
    TabOrder = 2
  end
  object rgPosition: TRadioGroup
    Left = 8
    Top = 67
    Width = 237
    Height = 53
    Caption = 'Position'
    Columns = 4
    Items.Strings = (
      'Left'
      'Top'
      'Right'
      'Bottom')
    TabOrder = 3
  end
  object GroupBox1: TGroupBox
    Left = 8
    Top = 126
    Width = 237
    Height = 53
    Caption = 'Splitter'
    TabOrder = 4
    object cbSplitterEnabled: TCheckBox
      Left = 8
      Top = 20
      Width = 61
      Height = 17
      Caption = 'Enabled'
      TabOrder = 0
    end
    object cbSplitterColor: TColorBox
      Left = 71
      Top = 18
      Width = 145
      Height = 22
      TabOrder = 1
    end
  end
end
