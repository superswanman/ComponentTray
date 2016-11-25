unit UComponentTray;

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.Generics.Collections,
  System.Rtti, System.TypInfo, FMX.Types, FMX.Controls, FMX.Forms, ToolsAPI,
  ComponentDesigner, EmbeddedFormDesigner, DesignIntf, Events, PaletteAPI,
  DesignMenus, DesignEditors, VCLMenus, FMXFormContainer, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.ExtCtrls, Vcl.ComCtrls, Vcl.Menus, Vcl.Dialogs,
  Vcl.Tabs, Vcl.ImgList, System.IniFiles;

procedure Register;

implementation

type
  TDesignNotification = class(TInterfacedObject, IDesignNotification)
  public
    procedure ItemDeleted(const ADesigner: IDesigner; AItem: TPersistent);
    procedure ItemInserted(const ADesigner: IDesigner; AItem: TPersistent);
    procedure ItemsModified(const ADesigner: IDesigner);
    procedure SelectionChanged(const ADesigner: IDesigner;
      const ASelection: IDesignerSelections);
    procedure DesignerOpened(const ADesigner: IDesigner; AResurrecting: Boolean);
    procedure DesignerClosed(const ADesigner: IDesigner; AGoingDormant: Boolean);
  end;

  TComponentEditorMenuItem = class(TMenuItem)
  private
    FComponentEditor: IComponentEditor;
    FVerbIndex: Integer;
  public
    constructor Create(AOwner: TComponent; AComponentEditor: IComponentEditor;
      AVerbIndex: Integer); reintroduce;
    procedure Click; override;
    property ComponentEditor: IComponentEditor read FComponentEditor;
  end;

  TSelectionEditorMenuItem = class(TMenuItem)
  private
    FSelectionEditor: ISelectionEditor;
    FVerbIndex: Integer;
    FSelections: IDesignerSelections;
  public
    constructor Create(AOwner: TComponent; ASelectionEditor: ISelectionEditor;
      AVerbIndex: Integer; ASelections: IDesignerSelections); reintroduce;
    procedure Click; override;
    property SelectionEditor: ISelectionEditor read FSelectionEditor;
  end;

  TComponentTray = class(TPanel)
  private
    FListView: TListView;
    FSplitter: TSplitter;
    procedure ListViewKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ListViewMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure ListViewSelect(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure ListViewContextPopup(Sender: TObject; MousePos: TPoint; var Handled: Boolean);
    procedure SplitterMoved(Sender: TObject);
    procedure LoadSettings;
    procedure SaveSettings;
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure AddItem(AItem: TPersistent);
    procedure RemoveItem(AItem: TPersistent);
    procedure UpdateItems(DoReplace: Boolean = False);
    procedure UpdateSelection(const ASelection: IDesignerSelections);
    procedure ChangeAlign(AValue: TAlign);
  end;

  TComponentPopupMenu = class(TPopupMenu)
    mnuNVCBStyle: TMenuItem;
    mnuNVCBPosition: TMenuItem;
  private
    FMenuLine: TMenuItem;
{$IFDEF DEBUG}
    procedure TestClick(Sender: TObject);
{$ENDIF}
    procedure StyleClick(Sender: TObject);
    procedure PositionClick(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
    procedure BuildContextMenu;
  end;

  TPropFieldNotifyEvent = procedure(Sender: TObject{TPropField}) of object;

  TComponentImageList = class
  private
    FImageList: TImageList;
    FImageDict: TDictionary<TClass,Integer>;
  public
    constructor Create;
    destructor Destroy; override;
    function AddOrGet(AClass: TClass): Integer;
    property ImageList: TImageList read FImageList;
  end;

var
  FOrgTEditorFormDesignerAfterConstruction: procedure(Self: TObject);
  FTrays: TObjectList<TComponentTray>;
  FCompImageList: TComponentImageList;
  FShowNonVisualComponentsChange: TPropFieldNotifyEvent;
  FShowNonVisualComponentsValueProp: PPropInfo;
  FShowNonVisualComponentsOnChangeProp: PPropInfo;
  FEditorViewsChangedEvent: ^TEvent;
  FDesignNotification: IDesignNotification;
  FComponentDeleting: Boolean;
  FComponentSelecting: Boolean;

function IsNonVisualComponent(Instance: TPersistent): Boolean;
begin
  Result := (Instance <> nil) and
            (Instance is TComponent) and
            not (Instance is Vcl.Controls.TControl) and
            not (Instance is FMX.Controls.TControl) and
            not (Instance is FMX.Forms.TCommonCustomForm);
end;

procedure HideNonVisualComponents;
var
  surface: IComponentDesignSurface;
  options: TDesignerOptions;
  surfaceOptions: TDesignSurfaceOptions;

  function GetComponentDesignSurface: IComponentDesignSurface;
  var
    ctx: TRttiContext;
    typ: TRttiType;
    fld: TRttiField;
  begin
    typ := ctx.GetType(TComponentRoot);
    if typ = nil then Exit;
    fld := typ.GetField('FSurface');
    if fld = nil then Exit;
    Result := IComponentDesignSurface(fld.GetValue((ActiveRoot as IInternalRoot).Implementor).AsInterface);
  end;

begin
  if ActiveRoot = nil then Exit;
  if ActiveRoot.Root is TDataModule then Exit;
  surface := GetComponentDesignSurface;
  if surface = nil then Exit;

  (BorlandIDEServices as IOTAServices).GetEnvironmentOptions.Values['ShowNonVisualComponents'] := False;

  ActiveDesigner.Environment.GetDesignerOptions(options);
  options.ShowNonVisualComponents := False;
  surfaceOptions.DisplayGrid := options.DisplayGrid;
  surfaceOptions.GridSize := Point(options.GridSizeX, options.GridSizeY);
  surfaceOptions.ShowComponentCaptions := options.ShowComponentCaptions;
  surfaceOptions.ShowDesignerHints := options.ShowDesignerHints;
  surfaceOptions.ShowNonVisualComponents := options.ShowNonVisualComponents;
  surfaceOptions.ShowExtendedControlHints := options.ShowExtendedControlHints;
  surface.SetOptions(surfaceOptions);
end;

function GetComponentTray(AControl: TWinControl): TComponentTray;
var
  i: Integer;
begin
  if AControl is TComponentTray then
    Exit(TComponentTray(AControl));
  for i := 0 to AControl.ControlCount-1 do
    if AControl.Controls[i] is TWinControl then
    begin
      Result := GetComponentTray(TWinControl(AControl.Controls[i]));
      if Result <> nil then Exit;
    end;
  Result := nil;
end;

function GetEditWindow(Control: TWinControl): TWinControl;
begin
  Result := Control;
  while Result <> nil do
  begin
    if Result.ClassName = 'TEditWindow' then
      Exit;
    Result := Result.Parent;
  end;
end;

{ TDesignNotification }

function GetFmxVclHost(Obj: TFmxObject): TWinControl;
var
  ctx: TRttiContext;
  typ: TRttiType;
  fld: TRttiField;
begin
  Result := nil;
  if Obj = nil then Exit;

  while Obj.Parent <> nil do
    Obj := Obj.Parent;
  if not (Obj is FMXFormContainer.TFormContainerForm) then Exit;

  typ := ctx.GetType(FMXFormContainer.TFormContainerForm);
  if typ = nil then Exit;
  fld := typ.GetField('FVclHost');
  if fld = nil then Exit;
  Result := TWinControl(fld.GetValue(Obj).AsObject);
end;

function GetComponentTrayByItem(AItem: TPersistent): TComponentTray;
var
  editWindow: TWinControl;
  vclhost: TWinControl;
begin
  Result := nil;
  if not IsNonVisualComponent(AItem) then Exit;
  if TComponent(AItem).Owner = nil then Exit;

  if TComponent(AItem).Owner is TWinControl then
  begin
    editWindow := GetEditWindow(TWinControl(TComponent(AItem).Owner));
    if editWindow = nil then Exit;
    Result := GetComponentTray(editWindow);
  end
  else if TComponent(AItem).Owner is TFmxObject then
  begin
    vclhost := GetFmxVclHost(TFmxObject(TComponent(AItem).Owner));
    if vclhost <> nil then
    begin
      editWindow := GetEditWindow(vclhost);
      if editWindow <> nil then
        Result := GetComponentTray(editWindow);
    end;
  end;
end;

function GetComponentTrayByDesigner(ADesigner: IDesigner): TComponentTray;
var
  comp: TComponent;
  editWindow: TWinControl;
  vclhost: TWinControl;
begin
  Result := nil;
  if not Assigned(ADesigner) then Exit;
  comp := ADesigner.Root;
  if not Assigned(comp) then Exit;

  if comp is TWinControl then
  begin
    editWindow := GetEditWindow(TWinControl(comp));
    if editWindow <> nil then
      Result := GetComponentTray(editWindow);
  end
  else if comp is TFmxObject then
  begin
    vclhost := GetFmxVclHost(TFmxObject(comp));
    if vclhost <> nil then
    begin
      editWindow := GetEditWindow(vclhost);
      if editWindow <> nil then
        Result := GetComponentTray(editWindow);
    end;
  end;
end;

procedure TDesignNotification.ItemDeleted(const ADesigner: IDesigner; AItem: TPersistent);
var
  componentTray: TComponentTray;
begin
  if FComponentDeleting then Exit;

  if not IsNonVisualComponent(AItem) then Exit;
  componentTray := GetComponentTrayByItem(AItem);
  if componentTray = nil then Exit;

  componentTray.RemoveItem(AItem);
end;

procedure TDesignNotification.ItemInserted(const ADesigner: IDesigner; AItem: TPersistent);
var
  componentTray: TComponentTray;
begin
  if not IsNonVisualComponent(AItem) then Exit;
  componentTray := GetComponentTrayByItem(AItem);
  if componentTray = nil then Exit;

  componentTray.AddItem(AItem);
  HideNonVisualComponents;
end;

procedure TDesignNotification.ItemsModified(const ADesigner: IDesigner);
var
  componentTray: TComponentTray;
begin
  componentTray := GetComponentTrayByDesigner(ADesigner);
  if componentTray = nil then Exit;

  componentTray.UpdateItems;
  HideNonVisualComponents;
end;

procedure TDesignNotification.SelectionChanged(const ADesigner: IDesigner;
  const ASelection: IDesignerSelections);
var
  tray: TComponentTray;
begin
  if FComponentDeleting or FComponentSelecting then Exit;

  tray := GetComponentTrayByDesigner(ADesigner);
  if tray = nil then Exit;
  tray.UpdateSelection(ASelection);
end;

procedure TDesignNotification.DesignerOpened(const ADesigner: IDesigner; AResurrecting: Boolean);
begin
  { Do nothing }
end;

procedure TDesignNotification.DesignerClosed(const ADesigner: IDesigner; AGoingDormant: Boolean);
begin
  { Do nothing }
end;

{ TComponentEditorMenuItem }

constructor TComponentEditorMenuItem.Create(AOwner: TComponent;
  AComponentEditor: IComponentEditor; AVerbIndex: Integer);
var
  wrapper: IMenuItem;
begin
  inherited Create(AOwner);
  FComponentEditor := AComponentEditor;
  FVerbIndex := AVerbIndex;

  Caption := FComponentEditor.GetVerb(FVerbIndex);
  wrapper := TMenuItemWrapper.Create(Self);
  FComponentEditor.PrepareItem(FVerbIndex, wrapper);
end;

procedure TComponentEditorMenuItem.Click;
begin
  inherited;
  if Enabled then
  begin
    if not Assigned(FComponentEditor) then Exit;
    if (FVerbIndex < 0) or (FVerbIndex >= FComponentEditor.GetVerbCount) then Exit;
    FComponentEditor.ExecuteVerb(FVerbIndex);

    FComponentEditor := nil;
    FVerbIndex := -1;
  end;
end;

{ TSelectionEditorMenuItem }

constructor TSelectionEditorMenuItem.Create(AOwner: TComponent;
  ASelectionEditor: ISelectionEditor; AVerbIndex: Integer;
  ASelections: IDesignerSelections);
var
  wrapper: IMenuItem;
begin
  inherited Create(AOwner);
  FSelectionEditor := ASelectionEditor;
  FVerbIndex := AVerbIndex;
  FSelections := ASelections;

  Caption := FSelectionEditor.GetVerb(FVerbIndex);
  wrapper := TMenuItemWrapper.Create(Self);
  FSelectionEditor.PrepareItem(FVerbIndex, wrapper);
end;

procedure TSelectionEditorMenuItem.Click;
begin
  if Enabled then
  begin
    if not Assigned(FSelectionEditor) then Exit;
    if (FVerbIndex < 0) or (FVerbIndex >= FSelectionEditor.GetVerbCount) then Exit;
    if not Assigned(FSelections) then Exit;
    FSelectionEditor.ExecuteVerb(FVerbIndex, FSelections);

    FSelectionEditor := nil;
    FVerbIndex := -1;
    FSelections := nil;
  end;
end;

{ TComponentTray }

constructor TComponentTray.Create(AOwner: TComponent);
begin
  inherited;
  Align := alLeft;
  Height := 80;
  Width := 120;
  Parent := TWinControl(AOwner);

  FListView := TListView.Create(Self);
  FListView.BorderStyle := bsNone;
  FListView.IconOptions.AutoArrange := True;
  FListView.IconOptions.Arrangement := iaTop;
  FListView.PopupMenu := TComponentPopupMenu.Create(Self);
  FListView.ViewStyle := vsSmallIcon;
  FListView.ReadOnly := True;
  FListView.MultiSelect := True;
  FListView.Parent := Self;
  FListView.Align := alClient;
  FListView.LargeImages := FCompImageList.ImageList;
  FListView.SmallImages := FCompImageList.ImageList;
  FListView.OnKeyDown := ListViewKeyDown;
  FListView.OnMouseDown := ListViewMouseDown;
  FListView.OnSelectItem := ListViewSelect;
  FListView.OnContextPopup := ListViewContextPopup;

  FSplitter := TSplitter.Create(Self);
  FSplitter.Align := alLeft;
  FSplitter.ResizeStyle := rsPattern;
  FSplitter.Color := clBackground;
  FSplitter.Parent := Parent;
  FSplitter.OnMoved := SplitterMoved;

  LoadSettings;
end;

procedure TComponentTray.LoadSettings;
var
  ini: TIniFile;
begin
  ini := TIniFile.Create(ChangeFileExt(GetModuleName(HInstance), '.ini'));
  try
    case ini.ReadInteger('Settings', 'Position', 0) of
      1: ChangeAlign(alTop);
      2: ChangeAlign(alRight);
      3: ChangeAlign(alBottom);
    end;
    Width := ini.ReadInteger('Settings', 'Width', 120);
    Height := ini.ReadInteger('Settings', 'Height', 80);
    if ini.ReadInteger('Settings', 'Style', 1) = 0 then
      FListView.ViewStyle := vsIcon
    else
      FListView.ViewStyle := vsSmallIcon;
  finally
    ini.Free;
  end;
end;

procedure TComponentTray.SaveSettings;
var
  ini: TIniFile;
begin
  ini := TIniFile.Create(ChangeFileExt(GetModuleName(HInstance), '.ini'));
  try
    case Align of
      alTop: ini.WriteInteger('Settings', 'Position', 1);
      alRight: ini.WriteInteger('Settings', 'Position', 2);
      alBottom: ini.WriteInteger('Settings', 'Position', 3);
    else
      ini.WriteInteger('Settings', 'Position', 0);
    end;
    ini.WriteInteger('Settings', 'Width', Width);
    ini.WriteInteger('Settings', 'Height', Height);
    if FListView.ViewStyle = vsIcon then
      ini.WriteInteger('Settings', 'Style', 0)
    else
      ini.WriteInteger('Settings', 'Style', 1);
  finally
    ini.Free;
  end;
end;
procedure TComponentTray.AddItem(AItem: TPersistent);
var
  li: TListItem;
begin
  if not IsNonVisualComponent(AItem) then Exit;
  if TComponent(AItem).Owner = nil then Exit;
  if TComponent(AItem).HasParent then Exit;

  // Ignore item that is not on current view
  if ActiveRoot.Root <> TComponent(AItem).Owner then Exit;

  FListView.ClearSelection;
  li := FListView.Items.Add;
  li.Caption := TComponent(AItem).Name;
  li.ImageIndex := FCompImageList.AddOrGet(AItem.ClassType);
  li.Data := AItem;
end;

procedure TComponentTray.RemoveItem(AItem: TPersistent);
var
  i: Integer;
begin
  if not IsNonVisualComponent(AItem) then Exit;
  if TComponent(AItem).HasParent then Exit;

  for i := 0 to FListView.Items.Count-1 do
  begin
    if FListView.Items[i].Data = AItem then
    begin
      FListView.Items[i].Delete;
      Break;
    end;
  end;
end;

procedure TComponentTray.UpdateItems(DoReplace: Boolean = False);
var
  root: IRoot;
  i: Integer;
  comp: TComponent;
  li: TListItem;
  tmp: TWinControl;
begin
  if not DoReplace then
  begin
    for i := 0 to FListView.Items.Count-1 do
      FListView.Items[i].Caption := TComponent(FListView.Items[i].Data).Name;
    Exit;
  end;

  FListView.Clear;

  root := ActiveRoot;
  if root = nil then Exit;

  // Disable when container is TDataModule
  if root.Root is TDataModule then
  begin
    Hide;
    Exit;
  end;

  // Insert after ViewSelector at FMX environment
  tmp := Parent;
  Parent := nil;
  Parent := tmp;
  FSplitter.Parent := nil;
  FSplitter.Parent := tmp;
  ChangeAlign(Align);

  HideNonVisualComponents;

  Show;

  for i := 0 to root.Root.ComponentCount-1 do
  begin
    comp := root.Root.Components[i];
    if IsNonVisualComponent(comp) then
    begin
      li := FListView.Items.Add;
      li.Caption := comp.Name;
      li.ImageIndex := FCompImageList.AddOrGet(comp.ClassType);
      li.Data := comp;
    end;
  end;
end;

procedure TComponentTray.UpdateSelection(const ASelection: IDesignerSelections);

  function Contains(AObj: TObject): Boolean;
  var
    i: Integer;
  begin
    for i := 0 to ASelection.Count-1 do
      if ASelection[i] = AObj then Exit(True);
    Result := False;
  end;

var
  i: Integer;
begin
  if ASelection.Count = 0 then
  begin
    FListView.ClearSelection;
    Exit;
  end;

  FListView.OnSelectItem := nil;
  try
    for i := 0 to FListView.Items.Count-1 do
      FListView.Items[i].Selected := Contains(TObject(FListView.Items[i].Data));
  finally
    FListView.OnSelectItem := ListViewSelect;
  end;
end;

procedure TComponentTray.ChangeAlign(AValue: TAlign);
var
  oldAlign: TAlign;
begin
  oldAlign := Align;
  Align := AValue;
  FSplitter.Align := AValue;

  if ((oldAlign in [alLeft, alRight]) and (Align in [alTop, alBottom]))
    or ((oldAlign in [alTop, alBottom]) and (Align in [alLeft, alRight])) then
  begin
    case Align of
      alLeft, alRight:
      begin
        Width := 120;
        FSplitter.Width := 3;
      end;
      alTop, alBottom:
      begin
        Height := 80;
        FSplitter.Height := 3;
      end;
    end;
  end;

  case FSplitter.Align of
    alLeft: FSplitter.Left := Self.Left + Self.Width;
    alTop: FSplitter.Top := Self.Top + Self.Height;
    alRight: FSplitter.Left := Self.Left;
    alBottom: FSplitter.Top := Self.Top;
  end;

  FListView.Align := alNone;
  FListView.Align := alClient;
end;

procedure TComponentTray.Notification(AComponent: TComponent;
  Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) and (AComponent is TComponentTray) then
  begin
    FTrays.Extract(TComponentTray(AComponent));
  end;
end;

procedure TComponentTray.ListViewKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  // Enable shortcuts
  TComponentPopupMenu(FListView.PopupMenu).BuildContextMenu;

  if (Key = VK_DELETE) and (Shift = []) then
  begin
    if ActiveRoot = nil then Exit;
    if FListView.SelCount = 0 then Exit;

    Key := 0;
    FListView.OnSelectItem := nil;
    try
      (ActiveRoot as IEditHandler).EditAction(eaDelete);
    finally
      FListView.OnSelectItem := ListViewSelect;
    end;
  end;
end;

procedure TComponentTray.ListViewMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  paletteServices: IOTAPaletteServices;
begin
  if Button <> mbLeft then Exit;

  paletteServices := BorlandIDEServices as IOTAPaletteServices;
  if paletteServices.SelectedTool = nil then Exit;
  FListView.OnSelectItem := nil;
  try
    paletteServices.SelectedTool.Execute;
    paletteServices.SelectedTool := nil;
    HideNonVisualComponents;
  finally
    FListView.OnSelectItem := ListViewSelect;
  end;
end;

procedure TComponentTray.ListViewSelect(Sender: TObject; Item: TListItem;
  Selected: Boolean);
var
  designer: IDesigner;
  selections: IDesignerSelections;
  i: Integer;
begin
  designer := ActiveRoot as IDesigner;
  if designer = nil then Exit;

  selections := CreateSelectionList;
  for i := 0 to FListView.Items.Count-1 do
    if FListView.Items[i].Selected then
      selections.Add(TPersistent(FListView.Items[i].Data));
  FComponentSelecting := True;
  try
    designer.SetSelections(selections);
  finally
    FComponentSelecting := False;
  end;
end;

procedure TComponentTray.ListViewContextPopup(Sender: TObject; MousePos: TPoint;
  var Handled: Boolean);
begin
  TComponentPopupMenu(FListView.PopupMenu).BuildContextMenu;
end;

procedure TComponentTray.SplitterMoved(Sender: TObject);
begin
  SaveSettings;
end;

{ TComponentPopupMenu }

constructor TComponentPopupMenu.Create(AOwner: TComponent);

  function NewRadioItem(const ACaption: string; AChecked: Boolean;
    AOnClick: TNotifyEvent; const AName: string): TMenuItem;
  begin
    Result := NewItem(ACaption, 0, AChecked, True, AOnClick, 0, AName);
    Result.RadioItem := True;
    Result.AutoCheck := True;
  end;

begin
  inherited;
  FMenuLine := NewLine;
  Items.Add(FMenuLine);
{$IFDEF DEBUG}
  Items.Add(NewItem('&Test', 0, False, True, TestClick, 0, 'mnuNVCBTest'));
{$ENDIF}

  mnuNVCBStyle := NewItem('&Style', 0, False, True, nil, 0, 'mnuNVCBStyle');
  Items.Add(mnuNVCBStyle);
  mnuNVCBStyle.Add(NewRadioItem('&Icon', False, StyleClick, 'mnuNVCBIcon'));
  mnuNVCBStyle.Add(NewRadioItem('&Tile', True, StyleClick, 'mnuNVCBTile'));

  mnuNVCBPosition := NewItem('&Position', 0, False, True, nil, 0, 'mnuNVCBPosition');
  Items.Add(mnuNVCBPosition);
  mnuNVCBPosition.Add(NewRadioItem('&Left', True, PositionClick, 'mnuNVCBLeft'));
  mnuNVCBPosition.Add(NewRadioItem('&Top', False, PositionClick, 'mnuNVCBTop'));
  mnuNVCBPosition.Add(NewRadioItem('&Right', False, PositionClick, 'mnuNVCBRight'));
  mnuNVCBPosition.Add(NewRadioItem('&Bottom', False, PositionClick, 'mnuNVCBBottom'));
end;

procedure TComponentPopupMenu.BuildContextMenu;
var
  selections: IDesignerSelections;
  selectionEditorList: ISelectionEditorList;
  i, j, insertPos: Integer;
  componentEditor: IComponentEditor;
  menuitem: TMenuItem;
begin
  // Remove menus that were added dynamicaly
  while FMenuLine.MenuIndex > 0 do
    Items.Delete(0);
  if ActiveRoot = nil then Exit;

  insertPos := 0;

  selections := CreateSelectionList;
  (ActiveRoot as IDesigner).GetSelections(selections);

  // Component menu
  if selections.Count = 1 then
  begin
    componentEditor := GetComponentEditor(TComponent(selections[0]), ActiveRoot as IDesigner);
    for i := 0 to componentEditor.GetVerbCount-1 do
    begin
      menuitem := TComponentEditorMenuItem.Create(Self, componentEditor, i);
      Items.Insert(insertPos, menuitem);
      Inc(insertPos);
    end;
    Items.Insert(insertPos, Vcl.Menus.NewLine);
    Inc(insertPos);
  end;

  // Selection menus
  selectionEditorList := GetSelectionEditors(ActiveRoot as IDesigner, selections);
  if selectionEditorList = nil then Exit;
  for i := 0 to selectionEditorList.Count-1 do
  begin
    for j := 0 to selectionEditorList[i].GetVerbCount-1 do
    begin
      menuitem := TSelectionEditorMenuItem.Create(Self, selectionEditorList[i], j, selections);
      Items.Insert(insertPos, menuitem);
      Inc(insertPos);
    end;
  end;

  if TComponentTray(Owner).FListView.ViewStyle = vsIcon then
    mnuNVCBStyle[0].Checked := True
  else
    mnuNVCBStyle[1].Checked := True;

  case TComponentTray(Owner).Align of
    alLeft: mnuNVCBPosition[0].Checked := True;
    alTop: mnuNVCBPosition[1].Checked := True;
    alRight: mnuNVCBPosition[2].Checked := True;
    alBottom: mnuNVCBPosition[3].Checked := True;
  end;
end;

{$IFDEF DEBUG}
procedure TComponentPopupMenu.TestClick(Sender: TObject);
begin
end;
{$ENDIF}

procedure TComponentPopupMenu.StyleClick(Sender: TObject);
begin
  case TMenuItem(Sender).MenuIndex of
    0: TComponentTray(Owner).FListView.ViewStyle := vsIcon;
    1: TComponentTray(Owner).FListView.ViewStyle := vsSmallIcon;
  end;
  TComponentTray(Owner).FListView.Arrange(arDefault);
  TComponentTray(Owner).SaveSettings;
end;

procedure TComponentPopupMenu.PositionClick(Sender: TObject);
begin
  case TMenuItem(Sender).MenuIndex of
    0: TComponentTray(Owner).ChangeAlign(alLeft);
    1: TComponentTray(Owner).ChangeAlign(alTop);
    2: TComponentTray(Owner).ChangeAlign(alRight);
    3: TComponentTray(Owner).ChangeAlign(alBottom);
  end;
  TComponentTray(Owner).SaveSettings;
end;

{ TComponentImageList }

constructor TComponentImageList.Create;
begin
  FImageList := TImageList.Create(nil);
  FImageList.Width := 24;
  FImageList.Height := 24;
  FImageList.DrawingStyle := dsTransparent;
  FImageDict := TDictionary<TClass,Integer>.Create;
end;

destructor TComponentImageList.Destroy;
begin
  FImageList.Free;
  FImageDict.Free;
  inherited;
end;

function TComponentImageList.AddOrGet(AClass: TClass): Integer;
const
  DEFAULT_ICON_NAME = 'DEFAULT24';
type
  TData = record
    Name: string;
    HInstance: THandle;
  end;
  PData = ^TData;
var
  cls: TClass;

  function EnumModuleProc(HInstance: NativeInt; Data: PData): Boolean;
  begin
    Result := True;
    if FindResource(HInstance, PChar(Data^.Name), RT_BITMAP) <> 0 then
    begin
      Data^.HInstance := HInstance;
      Result := False;
    end;
  end;

  function LoadIconImage(const Name: string): Integer;
  var
    bmp: TBitmap;
    data: TData;
  begin
    data.Name := Name;
    data.HInstance := 0;
    EnumModules(TEnumModuleFunc(@EnumModuleProc), @data);
    if data.HInstance <> 0 then
    begin
      bmp := TBitmap.Create;
      try
        bmp.LoadFromResourceName(data.HInstance, Name);
        bmp.Transparent := True;
        Result := FImageList.AddMasked(bmp, bmp.Canvas.Pixels[0, bmp.Height-1]);
        Exit;
      finally
        bmp.Free;
      end;
    end;
    Result := -1;
  end;

begin
  Result := -1;

  cls := AClass;
  while cls <> nil do
  begin
    if FImageDict.TryGetValue(cls, Result) then
    begin
      if cls <> AClass then
        FImageDict.Add(AClass, Result);
      Exit;
    end;

    Result := LoadIconImage(cls.ClassName);
    if Result <> -1 then
    begin
      FImageDict.Add(cls, Result);
      if cls <> AClass then
        FImageDict.Add(AClass, Result);
      Exit;
    end;

    cls := cls.ClassParent;
  end;

  // Load default icon
  if not FImageDict.TryGetValue(nil, Result) then
  begin
    Result := LoadIconImage(DEFAULT_ICON_NAME);
    FImageDict.Add(nil, Result);
  end;
  FImageDict.Add(AClass, Result);
end;

{ Functions }

procedure EditorViewsChanged(Self, Sender: TObject; NewTabIndex: Integer; NewViewIndex: Integer);
var
  viewBar: TTabSet;
  componentTray: TComponentTray;
begin
  if not (Sender is TComponent) then Exit;
  viewBar := TTabSet(TComponent(Sender).FindComponent('ViewBar'));
  if viewBar = nil then Exit;
  if viewBar.TabIndex = -1 then Exit;
  if NativeInt(viewBar.Tabs.Objects[viewBar.TabIndex]) <> 2 then Exit;

  componentTray := GetComponentTray(TWinControl(Sender));
  if componentTray = nil then Exit;
  componentTray.UpdateItems(True);
end;

procedure AddTray(EditorFormDesigner: TEditorFormDesigner);
begin
  FTrays.Add(TComponentTray.Create(EditorFormDesigner));
end;

procedure NewAfterConstruction(Self: TEditorFormDesigner);
begin
  if Assigned(FOrgTEditorFormDesignerAfterConstruction) then
    FOrgTEditorFormDesignerAfterConstruction(Self);
  AddTray(Self);
end;

function CreateMethod(Code, Data: Pointer): TMethod;
begin
  Result.Code := Code;
  Result.Data := Data;
end;

function Patch(Addr: Pointer; Value: Pointer): Pointer;
var
  oldProtect: DWORD;
begin
  Result := PPointer(Addr)^;
  VirtualProtect(Addr, SizeOf(Value), PAGE_READWRITE, oldProtect);
  PPointer(Addr)^ := Value;
  VirtualProtect(Addr, SizeOf(Value), oldProtect, nil);
  FlushInstructionCache(GetCurrentProcess, Addr, SizeOf(Value));
end;

procedure NewShowNonVisualComponentsChange(Self: TObject; Sender: TObject{TPropField});
var
  value: Variant;
begin
  if Assigned(FShowNonVisualComponentsValueProp) then
  begin
    value := GetVariantProp(Sender, FShowNonVisualComponentsValueProp);
    if value = True then
    begin
      // Force to hide non visual components
      SetVariantProp(Sender, FShowNonVisualComponentsValueProp, False);
      Exit;
    end;
  end;

  if Assigned(FShowNonVisualComponentsChange) then
  try
    FShowNonVisualComponentsChange(Sender);
  except
  end;
end;

procedure Register;
const
  sEditWindowList = '@Editorform@EditWindowList';
  sEditorViewsChangedEvent = '@Editorform@evEditorViewsChangedEvent';
  sTEditControlQualifiedName = 'EditorControl.TEditControl';
var
  ctx: TRttiContext;
  typ: TRttiType;
  prop: TRttiProperty;
  coreIdeName: string;
  editWindowList: ^TList;
  i: Integer;
  editorFormDesigner: TEditorFormDesigner;
  envOptions: TComponent;
  propShowNonVisualComponents: TComponent;
  method: TMethod;

  function FindEditorFormDesigner(AControl: TWinControl): TEditorFormDesigner;
  var
    i: Integer;
  begin
    if AControl.ClassType = TEditorFormDesigner then
      Exit(TEditorFormDesigner(AControl));
    for i := 0 to AControl.ControlCount-1 do
      if AControl.Controls[i] is TWinControl then
      begin
        Result := FindEditorFormDesigner(TWinControl(AControl.Controls[i]));
        if Assigned(Result) then Exit;
      end;
    Result := nil;
  end;

begin
  FTrays := TObjectList<TComponentTray>.Create;
  FCompImageList := TComponentImageList.Create;

{$WARN SYMBOL_DEPRECATED OFF}
  @FOrgTEditorFormDesignerAfterConstruction := Patch(Pointer(PByte(TEditorFormDesigner) + vmtAfterConstruction), @NewAfterConstruction);
{$WARN SYMBOL_DEPRECATED ON}

  coreIdeName := ExtractFileName(ctx.FindType(sTEditControlQualifiedName).Package.Name);
  editWindowList := GetProcAddress(GetModuleHandle(PChar(coreIdeName)), sEditWindowList);
  if editWindowList = nil then Exit;
  if editWindowList^ = nil then Exit;
  for i := 0 to editWindowList^.Count-1 do
  begin
    editorFormDesigner := FindEditorFormDesigner(TWinControl(editWindowList^[i]));
    if Assigned(editorFormDesigner) then
      AddTray(editorFormDesigner);
  end;

  FEditorViewsChangedEvent := GetProcAddress(GetModuleHandle(PChar(coreIdeName)), sEditorViewsChangedEvent);
  if FEditorViewsChangedEvent = nil then Exit;
  FEditorViewsChangedEvent^.Add(TNotifyEvent(CreateMethod(@EditorViewsChanged, nil)));

  FDesignNotification := TDesignNotification.Create;
  RegisterDesignNotification(FDesignNotification);

  envOptions := Application.FindComponent('EnvironmentOptions');
  if envOptions = nil then Exit;
  propShowNonVisualComponents := envOptions.FindComponent('ShowNonVisualComponents');
  if propShowNonVisualComponents = nil then Exit;
  typ := ctx.GetType(propShowNonVisualComponents.ClassType);
  if typ = nil then Exit;
  prop := typ.GetProperty('Value');
  if prop = nil then Exit;
  FShowNonVisualComponentsValueProp := TRttiInstanceProperty(prop).PropInfo;
  prop := typ.GetProperty('OnChange');
  if prop = nil then Exit;
  FShowNonVisualComponentsOnChangeProp := TRttiInstanceProperty(prop).PropInfo;
  TMethod(FShowNonVisualComponentsChange) := GetMethodProp(propShowNonVisualComponents, FShowNonVisualComponentsOnChangeProp);
  method := CreateMethod(@NewShowNonVisualComponentsChange, nil);
  SetMethodProp(propShowNonVisualComponents, FShowNonVisualComponentsOnChangeProp, method);

{$IFDEF DEBUG}
  OutputDebugString('Installed!');
{$ENDIF}
end;

procedure Unregister;
var
  envOptions: TComponent;
  propShowNonVisualComponents: TComponent;
  method: TMethod;
begin
{$WARN SYMBOL_DEPRECATED OFF}
  if Assigned(FOrgTEditorFormDesignerAfterConstruction) then
    Patch(Pointer(PByte(TEditorFormDesigner) + vmtAfterConstruction), @FOrgTEditorFormDesignerAfterConstruction);
{$WARN SYMBOL_DEPRECATED ON}

  if FEditorViewsChangedEvent <> nil then
  begin
    FEditorViewsChangedEvent^.Remove(TNotifyEvent(CreateMethod(@EditorViewsChanged, nil)));
  end;

  UnregisterDesignNotification(FDesignNotification);

  if Assigned(FShowNonVisualComponentsChange) then
  begin
    envOptions := Application.FindComponent('EnvironmentOptions');
    if envOptions <> nil then
    begin
      propShowNonVisualComponents := envOptions.FindComponent('ShowNonVisualComponents');
      if (propShowNonVisualComponents <> nil) and (FShowNonVisualComponentsOnChangeProp <> nil) then
      begin
        method := TMethod(FShowNonVisualComponentsChange);
        SetMethodProp(propShowNonVisualComponents, FShowNonVisualComponentsOnChangeProp, method);
      end;
    end;
  end;

  FTrays.Free;
  FCompImageList.Free;

{$IFDEF DEBUG}
  OutputDebugString('Uninstalled!');
{$ENDIF}
end;

initialization
finalization
  Unregister;
end.