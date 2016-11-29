unit UComponentTray;

interface

uses
  Winapi.Windows, System.SysUtils, System.Classes, System.Generics.Collections,
  System.Generics.Defaults, System.Rtti, System.TypInfo, FMX.Types,
  FMX.Controls, FMX.Forms, ToolsAPI, ComponentDesigner, EmbeddedFormDesigner,
  DesignIntf, Events, PaletteAPI, DesignMenus, DesignEditors, VCLMenus,
  FMXFormContainer, Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.ExtCtrls,
  Vcl.ComCtrls, Vcl.Menus, Vcl.Dialogs, Vcl.Tabs, Vcl.ImgList, System.IniFiles,
  Winapi.ActiveX;

procedure Register;

implementation

uses
  UComponentTray.SettingsDlg;

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

  TTypeData = record
    &Type: TClass;
    Count: Integer;
    Visible: Boolean;
  end;

  TComponentTray = class;

  TOTAPaletteDragAcceptor = class(TInterfacedObject, IOTAPaletteDragAcceptor, IOTADesignerDragAcceptor)
  private
    FControl: TComponentTray;
    { IOTAPaletteDragAcceptor }
    function GetHandle: THandle;
  public
    constructor Create(AControl: TComponentTray);
  end;

  TComponentTray = class(TPanel, IDropTarget)
  private
    FListView: TListView;
    FSplitter: TSplitter;
    FSortType: Integer;
    FAcceptor: IOTAPaletteDragAcceptor;
    FAcceptorIndex: Integer;
    FDragAllowed: Boolean;
    FTypes: TDictionary<TClass,TTypeData>;
    procedure ListViewKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ListViewMouseDown(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure ListViewDblClick(Sender: TObject);
    procedure ListViewSelect(Sender: TObject; Item: TListItem; Selected: Boolean);
    procedure ListViewContextPopup(Sender: TObject; MousePos: TPoint; var Handled: Boolean);
    procedure ListViewCompareCreationOrder(Sender: TObject; Item1, Item2: TListItem;
      Data: Integer; var Compare: Integer);
    procedure ListViewCompareName(Sender: TObject; Item1, Item2: TListItem;
      Data: Integer; var Compare: Integer);
    procedure ListViewCompareType(Sender: TObject; Item1, Item2: TListItem;
      Data: Integer; var Compare: Integer);
    procedure SplitterMoved(Sender: TObject);
    procedure LoadSettings;
    procedure SaveSettings;
    class procedure UpdateTrays(Style, Position: Integer;
      SplitterEnabled: Boolean; SplitterColor: TColor); static;
    { IDropTarget }
    function DropTarget_DragEnter(const dataObj: IDataObject; grfKeyState: Longint;
      pt: TPoint; var dwEffect: Longint): HResult; stdcall;
    function DropTarget_DragOver(grfKeyState: Longint; pt: TPoint;
      var dwEffect: Longint): HResult; stdcall;
    function DropTarget_DragLeave: HResult; stdcall;
    function DropTarget_Drop(const dataObj: IDataObject; grfKeyState: Longint; pt: TPoint;
      var dwEffect: Longint): HResult; stdcall;
    function IDropTarget.DragEnter = DropTarget_DragEnter;
    function IDropTarget.DragOver = DropTarget_DragOver;
    function IDropTarget.DragLeave = DropTarget_DragLeave;
    function IDropTarget.Drop = DropTarget_Drop;
  protected
    procedure CreateWnd; override;
    procedure DestroyWnd; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure AddItem(AItem: TPersistent);
    procedure RemoveItem(AItem: TPersistent);
    procedure UpdateCaptions;
    procedure UpdateItems(DoReplace: Boolean = False);
    procedure UpdateSelection(const ASelection: IDesignerSelections);
    procedure ChangeAlign(AValue: TAlign);
    procedure Sort(SortType: Integer = -1);
  end;

  TComponentPopupMenu = class(TPopupMenu)
    mnuNVCBFilter: TMenuItem;
    mnuNVCBSort: TMenuItem;
  private
    FMenuLine: TMenuItem;
{$IFDEF DEBUG}
    procedure TestClick(Sender: TObject);
{$ENDIF}
    procedure FilterClick(Sender: TObject);
    procedure FilterCheckAllClick(Sender: TObject);
    procedure FilterUncheckAllClick(Sender: TObject);
    procedure SortClick(Sender: TObject);
    procedure SettingsClick(Sender: TObject);
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

function IsNonVisualComponent(AClass: TClass): Boolean; overload;
begin
  Result := (AClass <> nil)
            and AClass.InheritsFrom(TComponent)
            and not AClass.InheritsFrom(Vcl.Controls.TControl)
            and not AClass.InheritsFrom(FMX.Controls.TControl)
            and not AClass.InheritsFrom(FMX.Forms.TCommonCustomForm);
end;

function IsNonVisualComponent(Instance: TPersistent): Boolean; overload;
begin
  Result := (Instance <> nil) and IsNonVisualComponent(Instance.ClassType);
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

function ViewStyleToInt(Value: TViewStyle): Integer;
begin
  Result := Ord(Value);
end;

function IntToViewStyle(Value: Integer): TViewStyle;
begin
  if (Value >= Ord(vsIcon)) and (Value <= Ord(vsList)) then
    Result := TViewStyle(Value)
  else
    Result := vsSmallIcon;
end;

function AlignToInt(Value: TAlign): Integer;
begin
  case Value of
    alLeft: Result := 0;
    alTop: Result := 1;
    alRight: Result := 2;
    alBottom: Result := 3;
  else
    Result := 0;
  end;
end;

function IntToAlign(Value: Integer): TAlign;
begin
  case Value of
    0: Result := alLeft;
    1: Result := alTop;
    2: Result := alRight;
    3: Result := alBottom;
  else
    Result := alLeft;
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

  componentTray.UpdateCaptions;
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

{ TOTAPaletteDragAcceptor }

constructor TOTAPaletteDragAcceptor.Create(AControl: TComponentTray);
begin
  inherited Create;
  FControl := AControl;
end;

function TOTAPaletteDragAcceptor.GetHandle: THandle;
begin
  RevokeDragDrop(FControl.Handle);
  Result := FControl.Handle;
  RegisterDragDrop(FControl.Handle, FControl);
end;

{ TComponentTray }

constructor TComponentTray.Create(AOwner: TComponent);
begin
  inherited;
  Align := alLeft;
  Height := 80;
  Width := 120;
  Parent := TWinControl(AOwner);

  FTypes := TDictionary<TClass,TTypeData>.Create;

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
  FListView.OnDblClick := ListViewDblClick;
  FListView.OnSelectItem := ListViewSelect;
  FListView.OnContextPopup := ListViewContextPopup;
  FListView.SortType := stData;
  FListView.OnCompare := ListViewCompareCreationOrder;
  FSortType := 0;

  FSplitter := TSplitter.Create(Self);
  FSplitter.Align := alLeft;
  FSplitter.ResizeStyle := rsPattern;
  FSplitter.Color := clBackground;
  FSplitter.Parent := Parent;
  FSplitter.OnMoved := SplitterMoved;

  FAcceptor := TOTAPaletteDragAcceptor.Create(Self);
  FAcceptorIndex := (BorlandIDEServices as IOTAPaletteServices).RegisterDragAcceptor(FAcceptor);

  LoadSettings;
end;

destructor TComponentTray.Destroy;
begin
  if FAcceptorIndex >= 0 then
    (BorlandIDEServices as IOTAPaletteServices).UnRegisterDragAcceptor(FAcceptorIndex);
  FAcceptor := nil;
  FTypes.Free;
  inherited;
end;

procedure TComponentTray.LoadSettings;
var
  ini: TIniFile;
begin
  ini := TIniFile.Create(ChangeFileExt(GetModuleName(HInstance), '.ini'));
  try
    FListView.ViewStyle := IntToViewStyle(ini.ReadInteger('Settings', 'Style', 1));
    ChangeAlign(IntToAlign(ini.ReadInteger('Settings', 'Position', 0)));
    FSplitter.Enabled := ini.ReadBool('Settings', 'SplitterEnabled', FSplitter.Enabled);
    FSplitter.Color := ini.ReadInteger('Settings', 'SplitterColor', Integer(FSplitter.Color));
    FSortType := ini.ReadInteger('Settings', 'SortType', FSortType);
    if (FSortType < 0) or (FSortType > 2) then
      FSortType := 0;
    Width := ini.ReadInteger('Settings', 'Width', 120);
    Height := ini.ReadInteger('Settings', 'Height', 80);
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
    ini.WriteInteger('Settings', 'Style', ViewStyleToInt(FListView.ViewStyle));
    ini.WriteInteger('Settings', 'Position', AlignToInt(Align));
    ini.WriteBool('Settings', 'SplitterEnabled', FSplitter.Enabled);
    ini.WriteInteger('Settings', 'SplitterColor', Integer(FSplitter.Color));
    ini.WriteInteger('Settings', 'SortType', FSortType);
    ini.WriteInteger('Settings', 'Width', Width);
    ini.WriteInteger('Settings', 'Height', Height);
  finally
    ini.Free;
  end;
end;

class procedure TComponentTray.UpdateTrays(Style, Position: Integer;
  SplitterEnabled: Boolean; SplitterColor: TColor);
var
  i: Integer;
begin
  for i := 0 to FTrays.Count-1 do
  begin
    FTrays[i].FListView.ViewStyle := IntToViewStyle(Style);
    FTrays[i].ChangeAlign(IntToAlign(Position));
    FTrays[i].FSplitter.Enabled := SplitterEnabled;
    FTrays[i].FSplitter.Color := SplitterColor;
  end;
end;

procedure TComponentTray.AddItem(AItem: TPersistent);
var
  li: TListItem;
  data: TTypeData;
begin
  if not IsNonVisualComponent(AItem) then Exit;
  if TComponent(AItem).Owner = nil then Exit;
  if TComponent(AItem).HasParent then
  begin
    if ActiveRoot = nil then Exit;
    if TComponent(AItem).GetParentComponent = nil then Exit;
    if ActiveRoot.Root <> TComponent(AItem).GetParentComponent then Exit;
  end;

  // Ignore item that is not on current view
  if ActiveRoot.Root <> TComponent(AItem).Owner then Exit;

  if not FTypes.TryGetValue(AItem.ClassType, data) then
  begin
    data.&Type := AItem.ClassType;
    data.Count := 0;
    data.Visible := True;
  end;
  Inc(data.Count);
  FTypes.AddOrSetValue(AItem.ClassType, data);

  // Filter
  if FTypes.TryGetValue(AItem.ClassType, data) then
    if not data.Visible then Exit;

  li := FListView.Items.Add;
  li.Caption := TComponent(AItem).Name;
  li.ImageIndex := FCompImageList.AddOrGet(AItem.ClassType);
  li.Data := AItem;
end;

procedure TComponentTray.RemoveItem(AItem: TPersistent);
var
  i: Integer;
  data: TTypeData;
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

  if FTypes.TryGetValue(AItem.ClassType, data) then
  begin
    Dec(data.Count);
    if data.Count = 0 then
      FTypes.Remove(AItem.ClassType)
    else
      FTypes[AItem.ClassType] := data;
  end;
end;

procedure TComponentTray.UpdateCaptions;
var
  i: Integer;
begin
  for i := 0 to FListView.Items.Count-1 do
    FListView.Items[i].Caption := TComponent(FListView.Items[i].Data).Name;
  Sort;
end;

procedure TComponentTray.UpdateItems(DoReplace: Boolean = False);
var
  root: IRoot;
  i: Integer;
  comp: TComponent;
  tmp: TWinControl;
  cls: TClass;
  data: TTypeData;
begin
  FListView.Clear;
  if not DoReplace then
  begin
    for cls in FTypes.Keys do
    begin
      data := FTypes[cls];
      data.Count := 0;
      FTypes[cls] := data;
    end;
  end
  else
    FTypes.Clear;

  root := ActiveRoot;
  if root = nil then Exit;

  // Disable when container is TDataModule
  if root.Root is TDataModule then
  begin
    Hide;
    Exit;
  end;

  if DoReplace then
  begin
    // Insert after ViewSelector at FMX environment
    tmp := Parent;
    Parent := nil;
    Parent := tmp;
    FSplitter.Parent := nil;
    FSplitter.Parent := tmp;
    ChangeAlign(Align);
  end;

  HideNonVisualComponents;

  Show;

  for i := 0 to root.Root.ComponentCount-1 do
  begin
    comp := root.Root.Components[i];
    AddItem(comp);
  end;
  for cls in FTypes.Keys do
  begin
    if FTypes[cls].Count = 0 then
      FTypes.Remove(cls);
  end;
  Sort;
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

procedure TComponentTray.Sort(SortType: Integer = -1);
begin
  if (SortType >= 0) and (SortType <= 2) then
  begin
    FSortType := SortType;
    case FSortType of
      0: FListView.OnCompare := ListViewCompareCreationOrder;
      1: FListView.OnCompare := ListViewCompareName;
      2: FListView.OnCompare := ListViewCompareType;
    end;
  end;
  FListView.AlphaSort;
end;

procedure TComponentTray.CreateWnd;
begin
  inherited;
  RegisterDragDrop(Handle, Self);
end;

procedure TComponentTray.DestroyWnd;
begin
  RevokeDragDrop(Handle);
  inherited;
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

procedure TComponentTray.ListViewDblClick(Sender: TObject);
begin
  if FListView.ItemIndex = -1 then Exit;
  if ActiveRoot = nil then Exit;

  (ActiveRoot as IInternalRoot).Edit(TComponent(FListView.Items[FListView.ItemIndex].Data));
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

procedure TComponentTray.ListViewCompareCreationOrder(Sender: TObject;
  Item1, Item2: TListItem; Data: Integer; var Compare: Integer);
var
  idx1, idx2: Integer;
begin
  idx1 := TComponent(Item1.Data).ComponentIndex;
  idx2 := TComponent(Item2.Data).ComponentIndex;
  Compare := idx1 - idx2;
end;

procedure TComponentTray.ListViewCompareName(Sender: TObject;
  Item1, Item2: TListItem; Data: Integer; var Compare: Integer);
begin
  Compare := CompareText(TComponent(Item1.Data).Name, TComponent(Item2.Data).Name);
end;

procedure TComponentTray.ListViewCompareType(Sender: TObject;
  Item1, Item2: TListItem; Data: Integer; var Compare: Integer);
begin
  Compare := CompareText(TComponent(Item1.Data).ClassName, TComponent(Item2.Data).ClassName);
  if Compare = 0 then
    Compare := CompareText(TComponent(Item1.Data).Name, TComponent(Item2.Data).Name);
end;

procedure TComponentTray.SplitterMoved(Sender: TObject);
begin
  SaveSettings;
end;

function TComponentTray.DropTarget_DragEnter(const dataObj: IDataObject;
  grfKeyState: Longint; pt: TPoint; var dwEffect: Longint): HResult;
var
  getPaletteItem: IOTAGetPaletteItem;
  paletteDragDropOp: IOTAPaletteDragDropOp;
  componentPaletteItem: IOTAComponentPaletteItem;
  ctx: TRttiContext;
  typ: TRttiType;
begin
  FDragAllowed := False;
  Result := S_OK;
  dwEffect := DROPEFFECT_NONE;
  if not Supports(dataObj, IOTAGetPaletteItem, getPaletteItem) then Exit;
  if not Supports(getPaletteItem.GetPaletteItem, IOTAPaletteDragDropOp, paletteDragDropOp) then Exit;
  if not Supports(getPaletteItem.GetPaletteItem, IOTAComponentPaletteItem, componentPaletteItem) then Exit;

  typ := ctx.FindType(componentPaletteItem.UnitName + '.' + componentPaletteItem.ClassName);
  if typ = nil then Exit;
  if not (typ is TRttiInstanceType) then Exit;
  if not IsNonVisualComponent(TRttiInstanceType(typ).MetaclassType) then Exit;

  dwEffect := DROPEFFECT_COPY;
  FDragAllowed := True;
end;

function TComponentTray.DropTarget_DragOver(grfKeyState: Longint; pt: TPoint;
  var dwEffect: Longint): HResult;
begin
  Result := S_OK;
  if FDragAllowed then
    dwEffect := DROPEFFECT_COPY
  else
    dwEffect := DROPEFFECT_NONE;
end;

function TComponentTray.DropTarget_DragLeave: HResult;
begin
  Result := S_OK;
  FDragAllowed := False;
end;

function TComponentTray.DropTarget_Drop(const dataObj: IDataObject; grfKeyState: Longint;
  pt: TPoint; var dwEffect: Longint): HResult;
var
  getPaletteItem: IOTAGetPaletteItem;
begin
  Result := S_OK;
  dwEffect := DROPEFFECT_NONE;
  try
    if not FDragAllowed then Exit;
    if Supports(dataObj, IOTAGetPaletteItem, getPaletteItem) then
    begin
      getPaletteItem.GetPaletteItem.Execute;
      dwEffect := DROPEFFECT_COPY;
    end;
    ActiveDesigner.Environment.ResetCompClass;
  finally
    FDragAllowed := False;
  end;
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

  mnuNVCBFilter := NewItem('&Filter', 0, False, True, nil, 0, 'mnuNVCBFilter');
  Items.Add(mnuNVCBFilter);

  mnuNVCBSort := NewItem('S&ort', 0, False, True, nil, 0, 'mnuNVCBSort');
  Items.Add(mnuNVCBSort);
  mnuNVCBSort.Add(NewRadioItem('Sort by &Creation Order', True, SortClick, 'mnuNVCBSortByCreationOrder'));
  mnuNVCBSort.Add(NewRadioItem('Sort by &Name', False, SortClick, 'mnuNVCBSortByName'));
  mnuNVCBSort.Add(NewRadioItem('Sort by &Type', False, SortClick, 'mnuNVCBSortByType'));

  Items.Add(NewLine);

  Items.Add(NewItem('&Settings', 0, False, True, SettingsClick, 0, 'mnuNVCBSettings'));
end;

procedure TComponentPopupMenu.BuildContextMenu;
var
  selections: IDesignerSelections;
  selectionEditorList: ISelectionEditorList;
  i, j, insertPos: Integer;
  componentEditor: IComponentEditor;
  menuitem: TMenuItem;
  data: TTypeData;
  types: TList<TTypeData>;
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

  mnuNVCBFilter.Clear;
  mnuNVCBFilter.Visible := TComponentTray(Owner).FTypes.Count > 0;
  if mnuNVCBFilter.Visible then
  begin
    types := TList<TTypeData>.Create;
    try
      for data in TComponentTray(Owner).FTypes.Values do
        types.Add(data);
      types.Sort(TComparer<TTypeData>.Construct(
        function(const Left, Right: TTypeData): Integer
        begin
          Result := CompareText(Left.&Type.ClassName, Right.&Type.ClassName);
        end));
      for i := 0 to types.Count-1 do
      begin
        menuitem := NewItem(types[i].&Type.ClassName, 0, types[i].Visible, True, FilterClick, 0, '');
        menuitem.Tag := NativeInt(types[i].&Type);
        mnuNVCBFilter.Add(menuitem);
      end;
    finally
      types.Free;
    end;
    mnuNVCBFilter.Add(NewLine);
    mnuNVCBFilter.Add(NewItem('&Check All', 0, False, True, FilterCheckAllClick, 0, 'mnuNVCBFilterCheckAll'));
    mnuNVCBFilter.Add(NewItem('&Uncheck All', 0, False, True, FilterUncheckAllClick, 0, 'mnuNVCBFilterUncheckAll'));
  end;

  mnuNVCBSort[TComponentTray(Owner).FSortType].Checked := True;
end;

{$IFDEF DEBUG}
procedure TComponentPopupMenu.TestClick(Sender: TObject);
begin
end;
{$ENDIF}

procedure TComponentPopupMenu.FilterClick(Sender: TObject);
var
  cls: TClass;
  data: TTypeData;
begin
  cls := TClass(TMenuItem(Sender).Tag);
  if TComponentTray(Owner).FTypes.TryGetValue(cls, data) then
  begin
    data.Visible := not data.Visible;
    TComponentTray(Owner).FTypes[cls] := data;
    TComponentTray(Owner).UpdateItems(False);
  end;
end;

procedure TComponentPopupMenu.FilterCheckAllClick(Sender: TObject);
var
  cls: TClass;
  data: TTypeData;
begin
  for cls in TComponentTray(Owner).FTypes.Keys do
  begin
    data := TComponentTray(Owner).FTypes[cls];
    data.Visible := True;
    TComponentTray(Owner).FTypes[cls] := data;
  end;
  TComponentTray(Owner).UpdateItems(False);
end;

procedure TComponentPopupMenu.FilterUncheckAllClick(Sender: TObject);
var
  cls: TClass;
  data: TTypeData;
begin
  for cls in TComponentTray(Owner).FTypes.Keys do
  begin
    data := TComponentTray(Owner).FTypes[cls];
    data.Visible := False;
    TComponentTray(Owner).FTypes[cls] := data;
  end;
  TComponentTray(Owner).UpdateItems(False);
end;

procedure TComponentPopupMenu.SortClick(Sender: TObject);
begin
  TComponentTray(Owner).Sort(TMenuItem(Sender).MenuIndex);
  TComponentTray(Owner).SaveSettings;
end;

procedure TComponentPopupMenu.SettingsClick(Sender: TObject);
var
  style, position: Integer;
  splitterEnabled: Boolean;
  splitterColor: TColor;
begin
  style := ViewStyleToInt(TComponentTray(Owner).FListView.ViewStyle);
  position := AlignToInt(TComponentTray(Owner).Align);
  splitterEnabled := TComponentTray(Owner).FSplitter.Enabled;
  splitterColor := TComponentTray(Owner).FSplitter.Color;

  if ShowSettingsDlg(style, position, splitterEnabled, splitterColor) then
  begin
    TComponentTray.UpdateTrays(style, position, splitterEnabled, splitterColor);
    TComponentTray(Owner).SaveSettings;
  end;
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

  procedure SmoothResize(aBmp: TBitmap; NuWidth, NuHeight: Integer);
  type
    TRGBArray = array[Word] of TRGBTriple;
    pRGBArray = ^TRGBArray;
  var
    X, Y: Integer;
    xP, yP: Integer;
    xP2, yP2: Integer;
    SrcLine1, SrcLine2: pRGBArray;
    t3: Integer;
    z, z2, iz2: Integer;
    DstLine: pRGBArray;
    DstGap: Integer;
    w1, w2, w3, w4: Integer;
    Dst: TBitmap;
  begin
    if (aBmp.Width = NuWidth) and (aBmp.Height = NuHeight) then
      Exit;

    aBmp.PixelFormat := pf24Bit;

    Dst := TBitmap.Create;
    Dst.PixelFormat := pf24Bit;
    Dst.Width := NuWidth;
    Dst.Height := NuHeight;

    DstLine := Dst.ScanLine[0];
    DstGap := Integer(Dst.ScanLine[1]) - Integer(DstLine);

    xP2 := MulDiv(aBmp.Width - 1, $10000, Dst.Width);
    yP2 := MulDiv(aBmp.Height - 1, $10000, Dst.Height);
    yP := 0;

    for Y := 0 to Dst.Height - 1 do
    begin
      xP := 0;
      SrcLine1 := aBmp.ScanLine[yP shr 16];

      if (yP shr 16 < aBmp.Height - 1) then
        SrcLine2 := aBmp.ScanLine[Succ(yP shr 16)]
      else
        SrcLine2 := aBmp.ScanLine[yP shr 16];

      z2 := Succ(yP and $FFFF);
      iz2 := Succ((not yP) and $FFFF);
      for X := 0 to Dst.Width - 1 do
      begin
        t3 := xP shr 16;
        z := xP and $FFFF;
        w2 := MulDiv(z, iz2, $10000);
        w1 := iz2 - w2;
        w4 := MulDiv(z, z2, $10000);
        w3 := z2 - w4;
        DstLine[X].rgbtRed :=
          (SrcLine1[t3].rgbtRed * w1 + SrcLine1[t3 + 1].rgbtRed * w2 +
          SrcLine2[t3].rgbtRed * w3 + SrcLine2[t3 + 1].rgbtRed * w4) shr 16;
        DstLine[X].rgbtGreen :=
          (SrcLine1[t3].rgbtGreen * w1 + SrcLine1[t3 + 1].rgbtGreen * w2 +
          SrcLine2[t3].rgbtGreen * w3 + SrcLine2[t3 + 1].rgbtGreen * w4) shr 16;
        DstLine[X].rgbtBlue :=
          (SrcLine1[t3].rgbtBlue * w1 + SrcLine1[t3 + 1].rgbtBlue * w2 +
          SrcLine2[t3].rgbtBlue * w3 + SrcLine2[t3 + 1].rgbtBlue * w4) shr 16;
        Inc(xP, xP2);
      end;
      Inc(yP, yP2);
      DstLine := pRGBArray(Integer(DstLine) + DstGap);
    end;

    aBmp.Width := Dst.Width;
    aBmp.Height := Dst.Height;
    aBmp.Canvas.Draw(0, 0, Dst);
    Dst.Free;
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
        try
          if (bmp.Width <> 24) or (bmp.Height <> 24) then
            SmoothResize(bmp, 24, 24);
          Result := FImageList.AddMasked(bmp, bmp.Canvas.Pixels[0, bmp.Height-1]);
        except
          Result := -1;
        end;
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