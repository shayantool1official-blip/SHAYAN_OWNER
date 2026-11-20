local CharacterBase = {
  ServerRPC = {},
  ClientRPC = {},
  MulticastRPC = {},
  LuaEventContainer = {
    "DefaultLuaEventPlaceholder",
    "OnCharacterAnimInstanceInit",
    "OnCharacterAnimInstanceInitFrameDelay",
    "OnProjectileEffect",
    "OnUnmannedVehicleStateChange",
    "OnDSEnterSelfieMode",
    "OnDSExitSelfieMode",
    "EVENTID_CHARACTER_POSSESSED",
    "EVENTID_PAWN_PICK_UP_ITEM",
    "EVENTID_PLAYEREVENT_REVIVAL",
    "EVENTID_INGAME_BUILD_SUCCESS",
    "EVENTID_PLAYEREVENT_SCOPECHANGE",
    "EVENTID_CHARACTER_DIED_PRE",
    "EVENTID_LOCAL_HERO_ID_CHANGED",
    "EVENTID_HERO_ID_CHANGED",
    "EVENTID_INGAME_ON_PAWN_CAMP_CHANGED",
    "EVENTID_TAKE_DAMAGE",
    "EVENTID_PLAYEREVENT_CONSUMEITEM",
    "EVENTID_PLAYEREVENT_DROPITEM"
  }
}
local IngameTipsTools = require("GameLua.Mod.BaseMod.Common.UI.InGameTipsTools")
local BudgetScheduler = require("GameLua.Mod.BaseMod.Common.BudgetScheduler")
local EAvatarSlotType = import("EAvatarSlotType")
local EPawnState = import("EPawnState")
local ECharacterPoseState = import("ECharacterPoseType")
local GameLuaAPI = import("/Script/ShadowTrackerExtra.GameLuaAPI")
local ASTExtraPlayerController = import("/Script/ShadowTrackerExtra.STExtraPlayerController")
local ANewFakePlayerAIController = import("NewFakePlayerAIController")
local GamePlayTools = require("GameLua.Mod.BaseMod.Common.GamePlayTools")
local GameplayData = require("GameLua.GameCore.Data.GameplayData")
local GameComponentData = require("GameLua.GameCore.Data.GameComponentData")
local GameplayActorData = require("GameLua.GameCore.Data.GameplayActorData")
local EMovementMode = import("EMovementMode")
local ESTEPoseState = import("ESTEPoseState")
local USTExtraBlueprintFunctionLibrary = import("STExtraBlueprintFunctionLibrary")
local ECharacterHealthStatus = import("ECharacterHealthStatus")
local FHealthPredictShowData = import("HealthPredictShowData")
local ELifetimeCondition = import("ELifetimeCondition")

function _GetItemName(ItemID)
  local ItemConfig = CDataTable.GetTableData("Item", ItemID)
  return ItemConfig and ItemConfig.ItemName or ""
end

CharacterBase.ServerRPC.ServerRPC_FailPreJoinDance = {
  Reliable = true,
  Params = { import("/Script/Engine.Actor") }
}
CharacterBase.ClientRPC.ClientRPC_FailedToJoinDance = {
  Reliable = true,
  Params = { UEnums.EPropertyClass.Int }
}
CharacterBase.ClientRPC.ClientRPC_TryJoinDance = {
  Reliable = true,
  Params = { import("/Script/Engine.Actor"), UEnums.EPropertyClass.Int }
}
CharacterBase.ClientRPC.ClientRPC_ShowEffectAfterFruitBingo = {
  Reliable = true,
  Params = { UEnums.EPropertyClass.Str, UEnums.EPropertyClass.Str, UEnums.EPropertyClass.Int }
}
CharacterBase.ClientRPC.ClientRPC_PlayMontageCamera = {
  Reliable = true,
  Params = {
    import("/Script/CoreUObject.Vector"),
    UEnums.EPropertyClass.Float,
    UEnums.EPropertyClass.Float,
    UEnums.EPropertyClass.Str
  }
}
CharacterBase.MulticastRPC.ShowEffectAfterSelfRescueSucceed = { Reliable = true, Params = {} }
CharacterBase.MulticastRPC.ServerShowShowUIConfigUI = {
  Reliable = true,
  Params = { UEnums.EPropertyClass.Str }
}
CharacterBase.MulticastRPC.MultiCast_GenericRPC = {
  Reliable = true,
  Params = {
    UEnums.EPropertyClass.Int,
    { UEnums.EPropertyClass.Array, UEnums.EPropertyClass.Byte }
  }
}

function CharacterBase:ctor(selfType)
  self._SuperData = nil
  self.VehicleParachuteComponent = nil
  self.DefaultNetCullDistanceSq = 1600000000
  self.DiedTime = 0
  self.DiedPosition = FVector(0, 0, 0)
  self.TeammmatePositionWhenMeDied = {}
  self.DefaultFootStep = true
  self.tCorrectionSimulateRepData = { Timer = nil, CurRepLoc = nil, LastRepLoc = nil }
  self.LastAddBuffInstID = 0
  self.LastAddPawn = nil
  self.bDisableProne = false
end

function CharacterBase:GetLifetimeReplicatedProps()
  local RepTable = {
    { "bCableCarView", ELifetimeCondition.COND_None, UEnums.EPropertyClass.Bool },
    { "bIsPlayingLevelSequenceForShow", ELifetimeCondition.COND_None, UEnums.EPropertyClass.Bool },
    { "bCounterattacking", ELifetimeCondition.COND_None, UEnums.EPropertyClass.Bool }
  }
  return RepTable
end

function CharacterBase:_PostConstruct()
  CharacterBase.__super._PostConstruct(self)
  self:AddControlEventWithCondition(self, "OnAttrChangeEventDelegate", {
    AttrName = {
      "bUseDeadBox", "IsInUnderGroundArea", "IsAroundUndergroundEntry",
      "EmotePlayRate", "AreaID", "MapID", "DanceStageAreaState"
    }
  }, self.CharacterAttrChangeEvent, self)
  self:AddControlEvent(self, "OnPawnRespawnDelegate", self.HandleOnRespawn, self)
  self:AddControlEvent(self, "OnParachuteStateChanged", self.LuaHandleParachuteStateChanged, self)
  self:AddControlEvent(self, "OnRepParachuteStateDelegate", self.LuaHandleRepParachuteStateDelegate, self)
  self:AddControlEvent(self, "OnPlayerPoseChange", self.PlayerPoseChange, self)
  self:AddControlEvent(self, "OnAttachedToVehicle", self.HandleAttachedToVehicle, self)
  self:AddControlEvent(self, "OnDetachedFromVehicle", self.HandleDetachedFromVehicle, self)
  if not Client then
    self.DefaultNetCullDistanceSq = self.NetCullDistanceSquared
    self.UseNewParachuteMove = false
    self.bIsPlayingLevelSequenceForShow = false
    self:SetNetUpdateGroupID(2)
    self:AddControlEvent(self, "IsEnterNearDeathDelegate", self.HandleServerEnterNearDeathDelegate, self)
    self:AddControlEvent(self, "OnPlayerStartRescue", self.HandleOnPlayerStartRescue, self)
    self:AddControlEvent(self, "StateEnterHandler", self.HandleOnEnterState, self)
    self:AddControlEvent(self, "OnHandleSkillStartDelegate", self.HandleOnSkillStart, self)
  else
    self.bClientCanTriggerSkill = true
    self:AddControlEvent(self, "OnPreRepAttachment", self.HandleOnPreRepAttachment, self)
    self:AddControlEvent(self, "IsEnterNearDeathDelegate", self.HandleIsEnterNearDeathDelegate, self)
    self:AddCommonEvent(EVENTTYPE_APPLICATION_ACTIVE_STATE, EVENTID_APPLICATION_REACTIVATED_EX, self.OnApplicationReactivated, self)
  end
  self:AddControlEvent(self, "OnDeathDelegate", self.HandleDeathDelegate, self)
end

function CharacterBase:OnDestroyed()
  self:Dispose()
  CharacterBase.__super.OnDestroyed(self)
end

function CharacterBase:ReceiveOnPoolCreate() self:ResetAnimInstanceClass() end
function CharacterBase:CharacterIsRecycled() return false end

function CharacterBase:BroadcastFatalDamageInfoWrapperSimpleLua(Causer, Victim, DamageType, AdditionalParam, IsHeadShot)
  local FatalDamageSubsystem = SubsystemMgr:Get("FatalDamageSubsystem")
  if FatalDamageSubsystem then
    FatalDamageSubsystem:BroadcastFatalDamageInfoWrapperSimpleLua(Causer, Victim, DamageType, AdditionalParam, IsHeadShot)
  end
end

function CharacterBase:BroadcastFatalDamageInfoWrapperLua(Causer, Victim, DamageType, AdditionalParam, IsHeadShot, ResultHealthStatus, PreviousHealthStatus, WhoKillMe, KillerKillCount)
  local FatalDamageSubsystem = SubsystemMgr:Get("FatalDamageSubsystem")
  if FatalDamageSubsystem then
    FatalDamageSubsystem:BroadcastFatalDamageInfoWrapperLua(Causer, Victim, DamageType, AdditionalParam, IsHeadShot, ResultHealthStatus, PreviousHealthStatus, WhoKillMe, KillerKillCount)
  end
end

function CharacterBase:OnApplicationReactivated()
  self.FormReactivated = true
end

function CharacterBase:OnClientAddKnownMissingWeapon(ItemDefineID)
  local ItemID = ItemDefineID and ItemDefineID.TypeSpecificID
  if not ItemID or ItemID <= 0 then return end
  local TipsCD = 10
  local UGameplayStatics = import("GameplayStatics")
  local CurrentTime = UGameplayStatics.GetRealTimeSeconds(CGameWorld)
  if 0 <= CurrentTime then
    local LastTime = self.LastMissingWeaponTipsTime
    if type(LastTime) == "number" and CurrentTime >= LastTime and TipsCD > CurrentTime - LastTime then return end
    self.LastMissingWeaponTipsTime = CurrentTime
  end
  local ItemName = _GetItemName(ItemID)
  ShowNotice(LocUtil.LocalizeResFormat(8200003, ItemName), nil, 5)
end

function CharacterBase:HandleOnEnterState(nState)
  if not Client and self.bEnsure == true then
    self:RemoveControlEvent(self.Object, "StateEnterHandler")
    return
  end
  if self:HasAuthority() then
    local EPawnState = import("EPawnState")
    if nState ~= EPawnState.Dying and nState ~= EPawnState.Dead and nState ~= EPawnState.BeCarriedBack and nState ~= EPawnState.Dizziness and nState ~= EPawnState.Knock and nState ~= EPawnState.Arrest then
      local AFKReportorSubsystem = SubsystemMgr:Get("AFKReportorSubsystem")
      if AFKReportorSubsystem then
        local PlayerState = self:GetPlayerStateSafety()
        if PlayerState and slua.isValid(PlayerState) then
          AFKReportorSubsystem:PlayerHaveAction(PlayerState.UID)
        end
      end
    end
  end
end

function CharacterBase:HandleOnSkillStart(uSkillCharacter, SkillID)
  if self:HasAuthority() then
    local AFKReportorSubsystem = SubsystemMgr:Get("AFKReportorSubsystem")
    if AFKReportorSubsystem then
      local PlayerState = self:GetPlayerStateSafety()
      if PlayerState and slua.isValid(PlayerState) then
        AFKReportorSubsystem:PlayerHaveAction(PlayerState.UID)
      end
    end
  end
end

function CharacterBase:HandCharacterDoJump()
  if slua.isValid(self.STCharacterMovement) and self.STCharacterMovement.MovementMode == EMovementMode.MOVE_Walking then
    self.STCharacterMovement.Velocity.Z = self.STCharacterMovement.JumpZVelocity
    self.STCharacterMovement:SetMovementMode(EMovementMode.MOVE_Falling, 0)
    self:RemoveControlEvent(self, "CharacterDoJump")
    self:ServerTriggerJump()
    self:AddControlEvent(self, "CharacterDoJump", self.HandCharacterDoJump, self)
  end
end

function CharacterBase:HandleOnPreRepAttachment(uAttachParent, uAttachComponent, uAttachSocket, uLocationOffset, uRotationOffset, uRelativeScale3D)
  if uAttachParent and slua.isValid(uAttachParent) then
    if not Client.IsEnableDSGrayPublishFlag(2199023255552) or Client.IsEditor() then
      local ASTExtraVehicleBase = import("STExtraVehicleBase")
      if not Game:IsClassOf(uAttachParent, ASTExtraVehicleBase) then return end
      local RelativeLocation = FVector(0, 0, self:GetSimpleCollisionHalfHeightInStandPose())
      local uUseAttachComp
      if slua.isValid(uAttachComponent) then uUseAttachComp = uAttachComponent
      elseif uAttachParent.GetMesh then uUseAttachComp = uAttachParent:GetMesh() end
      local VehicleSeat = uAttachParent:GetVehicleSeats()
      if slua.isValid(VehicleSeat) and slua.isValid(uUseAttachComp) then
        local RealSocketName = VehicleSeat:GetAttachSocketName(self, uUseAttachComp, uAttachSocket)
        if RealSocketName ~= "None" then uAttachSocket = RealSocketName end
      end
      self:SetAttachment(uAttachParent, uUseAttachComp, RelativeLocation, uRotationOffset, uRelativeScale3D, uAttachSocket)
    end
  end
end

function CharacterBase:HandleIsEnterNearDeathDelegate(IsNearDeath)
  if self.HealthStatus == ECharacterHealthStatus.FinishedLastBreath and self.LastHealthStatus == ECharacterHealthStatus.HasLastBreath then
    if slua.isValid(self.Mesh) then
      self:CheckPlayDeadAnimation(self.Mesh.AnimScriptInstance)
      local uAnimInstances = self.Mesh:GetSubAnimInstances()
      for i = 1, uAnimInstances:Num() do
        self:CheckPlayDeadAnimation(uAnimInstances:Get(i - 1))
      end
    end
  end
  local ENetRole = import("ENetRole")
  local EParachuteState = import("EParachuteState")
  if self.Role == ENetRole.ROLE_AutonomousProxy and self.HealthStatus == ECharacterHealthStatus.HasLastBreath and self.ParachuteState == EParachuteState.PS_Opening then
    self:SwitchCameraToParachuteOpening()
  end
  self:ClearFollowEmote()
end

function CharacterBase:HandleServerEnterNearDeathDelegate(IsNearDeath)
  if IsNearDeath then
    local SilentCommunicationSubsystem = SubsystemMgr:Get("SilentCommunicationSubsystem")
    if SilentCommunicationSubsystem then
      SilentCommunicationSubsystem:OnConditionTrigger(1, self:GetPlayerControllerSafety())
    end
  end
end

function CharacterBase:GetSelfRescueSkillID()
  if self:HasState(EPawnState.AttachToOther) then return 0 end
  return 1014669
end

function CharacterBase:HandleOnPlayerStartRescue(RescueWho, IsRescuing)
  if RescueWho and slua.isValid(RescueWho) and RescueWho == self.Object then
    if IsRescuing then
      local uWeaponManager = self:GetWeaponManager()
      if Game:IsValid(uWeaponManager) then uWeaponManager.HideCurrentWeapon = true end
      self.CachedSelfRescueSkillID = self:GetSelfRescueSkillID()
      self:TriggerEntrySkillWithID(self.CachedSelfRescueSkillID, true)
      local PlayerState = self:GetPlayerStateSafety()
      if Game:IsValid(PlayerState) then PlayerState:AddGeneralCount(1121, 1, false) end
    else
      local SkillManager = self:GetSkillManager()
      if SkillManager and slua.isValid(SkillManager) and self.CachedSelfRescueSkillID then
        local UTSkillStopReason = import("UTSkillStopReason")
        SkillManager:StopSkill(self.CachedSelfRescueSkillID, UTSkillStopReason.SkillStopReason_Interrupted)
        self.CachedSelfRescueSkillID = nil
      end
      local uWeaponManager = self:GetWeaponManager()
      if Game:IsValid(uWeaponManager) then uWeaponManager.HideCurrentWeapon = false end
    end
  end
  if IsRescuing then
    local SilentCommunicationSubsystem = SubsystemMgr:Get("SilentCommunicationSubsystem")
    if SilentCommunicationSubsystem then
      SilentCommunicationSubsystem:OnConditionTrigger(2, self:GetPlayerControllerSafety())
    end
  else
    if not slua.isValid(RescueWho) or RescueWho == self.Object then return end
    if RescueWho:HasState(EPawnState.Dying) then return end
    local uController = RescueWho:GetPlayerControllerSafety()
    if not slua.isValid(uController) then return end
    local uPlayerState = uController.PlayerState
    if not slua.isValid(uPlayerState) then return end
    local nKillerPlayerKey = uPlayerState.NearDeathCauserId
    local uKillerPlayerState = GameplayData.GetPlayerState(nKillerPlayerKey)
    if slua.isValid(uKillerPlayerState) and uKillerPlayerState.TeamID == self.TeamID and uPlayerState ~= uKillerPlayerState then return end
    local SilentCommunicationSubsystem = SubsystemMgr:Get("SilentCommunicationSubsystem")
    if SilentCommunicationSubsystem then
      SilentCommunicationSubsystem:OnConditionTrigger(2, uController, uController, 31006, 0, true, nil)
    end
  end
end

function CharacterBase:HandleDeathDelegate()
  if Client then self:ClearFollowEmote() end
  if slua.isValid(self.STCharacterMovement) then
    self.STCharacterMovement:Deactivate()
    self.STCharacterMovement:SetMovementMode(EMovementMode.MOVE_None, 0)
  end
end

function CharacterBase:GetTargetAnimClass()
  if self.AvatarAnimClassCache ~= nil then return self.AvatarAnimClassCache end
  local uPC = self:GetPlayerControllerSafety()
  if slua.isValid(uPC) then return self.MainCharAnimClass end
  if self:IsInCarryBackState() then
    local uBeCarriedCharacter = self:GetBeCarriedBackCharacter()
    if slua.isValid(uBeCarriedCharacter) and slua.isValid(uBeCarriedCharacter:GetPlayerControllerSafety()) then
      return self.MainCharAnimClass
    end
  end
  return self.MainCharTPPAnimClass
end

function CharacterBase:ResetCharAnimInstanceClass(SetReason, bForceClearOldAnim)
  self.Super:ResetCharAnimInstanceClass(SetReason, bForceClearOldAnim)
end

function CharacterBase:CheckPlayDeadAnimation(uAnimInst)
  if slua.isValid(uAnimInst) and uAnimInst.PlayPlayerDeadAnimation ~= nil and uAnimInst.C_IsNearDeathStatus ~= nil then
    local bResetND = false
    if uAnimInst.C_IsNearDeathStatus == true then
      uAnimInst.C_IsNearDeathStatus = false
      bResetND = true
    end
    local PrePose = uAnimInst.C_PoseType
    uAnimInst.C_PoseType = ECharacterPoseState.ECharPose_Crouch
    uAnimInst:PlayPlayerDeadAnimation()
    if bResetND then uAnimInst.C_IsNearDeathStatus = true end
    uAnimInst.C_PoseType = PrePose
  end
end

function CharacterBase:SetDiedTime()
  self.DiedTime = CGameState:GetServerWorldTimeSeconds()
  local PlayerState = self:GetPlayerStateSafety()
  if PlayerState == nil or slua.isValid(PlayerState) == false or PlayerState.SetDiedTime == nil then return end
  PlayerState:SetDiedTime()
end

function CharacterBase:GetDiedTime() return self.DiedTime or 0 end

function CharacterBase:SetDiedPosition()
  self.DiedPosition = self:K2_GetActorLocation()
  self.TeammmatePositionWhenMeDied = {}
  local CharacterState = self:GetPlayerStateSafety()
  if CharacterState == nil then return end
  local TeammatesState = CharacterState.TeamMatePlayerStateList
  if TeammatesState == nil or TeammatesState:Num() <= 0 then return end
  for index = 0, TeammatesState:Num() - 1 do
    local uTeammatePlayerState = TeammatesState:Get(index)
    if uTeammatePlayerState and slua.isValid(uTeammatePlayerState) and slua.isValid(uTeammatePlayerState.TeamMatePlayerState) then
      local uOtherCharacter = uTeammatePlayerState.TeamMatePlayerState:GetPlayerCharacter()
      if uOtherCharacter and slua.isValid(uOtherCharacter) then
        self.TeammmatePositionWhenMeDied[uOtherCharacter.PlayerKey] = uOtherCharacter:K2_GetActorLocation()
      end
    end
  end
end

function CharacterBase:GetDiedPosition() return self.DiedPosition or FVector(0, 0, 0) end
function CharacterBase:GetTeammatePositionWhenMeDied() return self.TeammmatePositionWhenMeDied end

function CharacterBase:SetDiedPlayerCount()
  local uPlayerState = self:GetPlayerStateSafety()
  if uPlayerState == nil or slua.isValid(uPlayerState) == false then return end
  if uPlayerState.SetDiedPlayerCount == nil then return end
  uPlayerState:SetDiedPlayerCount()
end

function CharacterBase:ReceiveBeginPlay()
  CharacterBase.__super.ReceiveBeginPlay(self)
  GameplayData.BindPlayerCharacter(self.Object)
  BudgetScheduler.Submit(BudgetScheduler.Channel.Init, function()
    if slua.isValid(self.Object) then self.ConditionChangePhysicsAsset(self) end
  end, self.Object, "CharacterBase.ConditionChangePhysicsAsset")
  if Client then
    local AvatarExceptionSubsystem = SubsystemMgr:Get("AvatarExceptionSubsystem")
    if AvatarExceptionSubsystem then AvatarExceptionSubsystem:BindPlayerCharacter(self.Object) end
  end
  if self.LuaReceiveBeginPlay then self:LuaReceiveBeginPlay() end
  self:AddCommonEventWithConditions(EVENTTYPE_INGAME_NORMAL, EVENTID_GAME_MODE_STATE_CHANGE, { [1] = "FightingState" }, self.HandleEnterGameModeFightingState, self)
  self:CheckInitPlayerDSData()
  if self.DelayResetStandDuration ~= nil and self.DelayHideDuration ~= nil then
    self.DelayResetStandDuration = self.DelayHideDuration
  end
  if self:HasAuthority() and slua.isValid(self.NearDeatchComponent) then
    self:AddControlEvent(self.NearDeatchComponent, "OnPreEnterNearDeath", self.HandleOnPreEnterNearDeath, self)
  end
  if self:IsAutonomousProxy() and slua.isValid(self.STCharacterMovement) then
    self:AddControlEvent(self.STCharacterMovement, "OnClientAdjustPosition", self.HandleOnClientAdjustPosition, self)
    self.STCharacterMovement.ForbiddenMoveCondition.ContinueSeconds = 10
  end
  if CGame:IsEditor() then
    local SecurtyEditorConfig = GamePlayTools.GetCurrentConfig("SecurtyEditorConfig")
    if SecurtyEditorConfig and SecurtyEditorConfig.GameSafeCallbacks then require(SecurtyEditorConfig.GameSafeCallbacks) end
  end
  local UKismetSystemLibrary = import("KismetSystemLibrary")
  if UKismetSystemLibrary.IsDedicatedServer(self) and GameSafeCallbacks then
    GameSafeCallbacks.CharacterReceiveBeginPlay(self)
    self.bSkipComparePropertiesForReplay = true
  end
  if Client then self:AddControlEvent(self, "OnCharacterFallingModeChange", self.HandleCharacterFallingModeChange, self) end
  if self:HasAuthority() then
    local Config = require("GameLua.Mod.BaseMod.DS.Config.SelfRescueConfig")
    if Config then
      if Config.HurtWhenSelfRescue ~= nil then self.HurtWhenSelfRescue = Config.HurtWhenSelfRescue end
      if Config.CoolDownTime ~= nil then self.SelfRescueCoolDownTime = Config.CoolDownTime end
    end
    self:ReplaceGrenadeSkills()
  end
  if self:IsAutonomousProxy() then
    local CurrentVehicle = self:GetCurrentVehicle()
    if slua.isValid(CurrentVehicle) then self:ChangeCurrentVehicle(CurrentVehicle) end
    self:AddControlEvent(self, "OnClientCurrentVehicleChange", self.ChangeCurrentVehicle, self)
    local CurrentShootWeapon = self:GetCurrentShootWeapon()
    if slua.isValid(CurrentShootWeapon) then self:ChangeCurrentWeapon(CurrentShootWeapon) end
    GameComponentData.AddSelfWeaponManagerComponentEvent(self, "ChangeCurrentUsingWeaponDelegate", self.ChangeCurrentWeapon, self)
    GameComponentData.AddSelfWeaponManagerComponentEvent(self, "OnClientAddKnownMissingWeapon", self.OnClientAddKnownMissingWeapon, self)
    if self.ReportCharacterStateTimer then self:RemoveGameTimer(self.ReportCharacterStateTimer) end
    self.ReportCharacterStateTimer = self:AddGameTimer(5.0, true, function() self:ReportCharacterState() end)
  end
  if Client and self:IsAutonomousProxy() then self:RegistAttrModifyRecordList() end
  if Client then
    local uGameState = slua_GameFrontendHUD:GetGameState()
    if uGameState and slua.isValid(uGameState) and uGameState.GetGameModeState and uGameState:GetGameModeState() == "FightingState" then
      local NewObjectPoolLuaBridgeSubsystem = SubsystemMgr:Get("NewObjectPoolLuaBridgeSubsystem")
      if NewObjectPoolLuaBridgeSubsystem then
        NewObjectPoolLuaBridgeSubsystem.SpawnActorCounter_Character = NewObjectPoolLuaBridgeSubsystem.SpawnActorCounter_Character + 1
      end
    end
    if slua.isValid(self.STCharacterMovement) then
      self.STCharacterMovement.MoveSkipTickContinueTime = 2
      self.STCharacterMovement.MoveSkipTickContinueCount = 40
      self.STCharacterMovement.SimulateDelayReceiveLODTheshold = 16
      self.STCharacterMovement.SimulateNotMoveSmoothLODTheshold = 14
    end
    if Client.IsDevelopment() then self:DevelopmentClientCheck() end
    local ENetRole = import("ENetRole")
    if self.Role == ENetRole.ROLE_SimulatedProxy then self:RefreshThermalImagingLocal() end
  end
  if self:HasAuthority() and slua.isValid(self.STCharacterMovement) then
    self:AddControlEvent(self.STCharacterMovement, "OnComponentActivated", self.OnMovementActivated, self)
    self:AddControlEvent(self.STCharacterMovement, "OnResolvePenetrationDelegate", self.HandleOnResolvePenetrationDelegate, self)
  end
  local ENetRole = import("ENetRole")
  if self.Role == ENetRole.ROLE_AutonomousProxy and slua.isValid(self.STCharacterMovement) then
    self.STCharacterMovement.bOpenLocationSmoothOnDynamicMovementBase = false
  end
  self:ShowDoorInteractUIIfNeed()
  if Client then self:AddControlEvent(self, "OnSmartBearerLayerVisibilityChanged", self._OnSmartBearerLayerVisibilityChanged, self) end
end

function CharacterBase:_OnSmartBearerLayerVisibilityChanged(bIsHidden)
  local EMeshVisibleLayer = import("/Script/Engine.EMeshVisibleLayer")
  local ESkeletaTickMode = import("/Script/Engine.ESkeletaTickMode")
  local ShayanMesh = self.Mesh
  if slua.isValid(ShayanMesh) then
    if bIsHidden then
      ShayanMesh:SetLayerVisibilityValue(EMeshVisibleLayer.VisibleLayer_2, false, false)
      ShayanMesh:SetTickMode(ESkeletaTickMode.TICK_NONE)
    else
      ShayanMesh:SetLayerVisibilityValue(EMeshVisibleLayer.VisibleLayer_2, true, false)
      ShayanMesh:SetTickMode(ESkeletaTickMode.TICK_ALL)
    end
  end
end

function CharacterBase:ConditionChangePhysicsAsset()
  if Client then
    local uMyMesh = self.Mesh
    if slua.isValid(uMyMesh) then
      local uMyMeshPhysics = USTExtraBlueprintFunctionLibrary.GetPhysicsAssetFromMesh(uMyMesh)
      if uMyMeshPhysics == self.ShootPhysicsAsset and slua.isValid(self.ShootPhysicsAssetOpt) and uMyMesh.SetPhysicsAsset then
        uMyMesh:SetPhysicsAsset(self.ShootPhysicsAssetOpt, true)
        USTExtraBlueprintFunctionLibrary.CreatePhysicsState(uMyMesh)
      end
    end
  end
end

function CharacterBase:ShowDoorInteractUIIfNeed()
  local ENetRole = import("ENetRole")
  if Client and self.Role == ENetRole.ROLE_AutonomousProxy then
    self:AddGameTimer(1, false, function()
      local CapsuleComponent = self and self.CapsuleComponent
      if CapsuleComponent and slua.isValid(CapsuleComponent) then
        local ActorClass = import("/Script/Engine.Actor")
        local PUBGDoorClass = import("PUBGDoor")
        local OverlapActors = CapsuleComponent:GetOverlappingActors(slua.Array(UEnums.EPropertyClass.Object, ActorClass), PUBGDoorClass)
        if OverlapActors and OverlapActors:Num() > 0 then
          for Index = 0, OverlapActors:Num() - 1 do
            local PUBGDoor = OverlapActors:Get(Index)
            if PUBGDoor and slua.isValid(PUBGDoor) and PUBGDoor.bDoubleDoor == false and PUBGDoor.DoorBroken == false then
              local uHitResult = import("/Script/Engine.HitResult")()
              PUBGDoor:OnBeginOverlap(PUBGDoor.Interaction, self.Object, CapsuleComponent, -1, true, uHitResult)
            end
          end
        end
      end
    end)
  end
end

function CharacterBase:DevelopmentClientCheck()
  if slua.isValid(self.HitBox_Stand) or slua.isValid(self.HitBox_Prone) then
    local UKismetSystemLibrary = import("KismetSystemLibrary")
    if not UKismetSystemLibrary.IsStandalone(slua.getGameInstance()) then
      local Tips = "DevelopmentClientCheck: "
      Tips = Tips .. string.format("Character =  %s ", tostring(self.Object))
      Tips = Tips .. string.format("HitBox_Stand =  %s ", tostring(self.HitBox_Stand))
      Tips = Tips .. string.format("HitBox_Prone =  %s ", tostring(self.HitBox_Prone))
      self:RPC_Server_ShootVertifyFailAlarm(4, Tips)
    end
  end
end

function CharacterBase:IsAutonomousProxy()
  if CharacterBase.__super.IsAutonomousProxy(self) then return true end
  if Client and self.IsLocallyControlled and type(self.IsLocallyControlled) == "function" and self:IsLocallyControlled() then return true end
  return CharacterBase.__super.IsAutonomousProxy(self)
end

function CharacterBase:SetLastAddBuffInst(nInstID, uPawn)
  self.LastAddBuffInstID = nInstID
  self.LastAddPawn = uPawn
end
function CharacterBase:GetLastAddBuffInst() return self.LastAddBuffInstID, self.LastAddPawn end
function CharacterBase:RegistAttrModifyRecordList() end
function CharacterBase:ChangeCurrentVehicle(CurrentVehicle) GameplayActorData.BindSelfActor("CurrentVehicle", CurrentVehicle) end
function CharacterBase:ChangeCurrentWeapon()
  if self.GetCurrentWeapon == nil then return end
  local uWeapon = self:GetCurrentWeapon()
  if slua.isValid(uWeapon) then GameplayActorData.BindSelfActor("CurrentWeapon", uWeapon) end
end

function CharacterBase:HandleOnClientAdjustPosition(NewLocation, Reason)
  if CGameState == nil or not slua.isValid(CGameState) then return end
  if CGameState.GetGameModeState == nil or CGameState:GetGameModeState() == "ReadyState" then return end
  local EReason = import("ECharacterMoveDragReason")
  if Reason == EReason.CMDR_ExceedsDistance and self.PlayerState and self.PlayerState.Ping then
    local bWeakNet = self.PlayerState.Ping * 4 > 250 or false
    if bWeakNet then
      NetUtil.ShowDSTimeOutTipsUI(true, NetUtil.DSTimeOutShort)
      self:AddGameTimer(1, false, function() NetUtil.ShowDSTimeOutTipsUI(false, NetUtil.DSTimeOutShort) end)
    end
  end
end

function CharacterBase:CheckInitPlayerDSData()
  if self:IsAutonomousProxy() then
    if self.PlayerKey ~= nil and self.PlayerKey > 0 then
      self:InitPlayerDsData(self.PlayerKey)
    else
      self:AddControlEvent(self, "OnReceivePlayerKey", self.InitPlayerDsData, self)
    end
  end
end

function CharacterBase:InitPlayerDsData(nPlayerKey)
  if nPlayerKey == nil or nPlayerKey == 0 then return end
  local PlayerEventSubsystem = SubsystemMgr:Get("PlayerEventSystem")
  if PlayerEventSubsystem then PlayerEventSubsystem:CheckInitDSData(nPlayerKey) end
end

function CharacterBase:ReceiveEndPlay(nDeltaSeconds)
  BudgetScheduler.EvictOwner(BudgetScheduler.Channel.Init, self.Object)
  if Client then
    local SKillManager = self:GetSkillManager()
    local CheckWeaponSkillID = 1014405
    if slua.isValid(SKillManager) and SKillManager:GetCurSkillID() == CheckWeaponSkillID then self:StopCurrentLevelSequence() end
    if self.ReportCharacterStateTimer then
      self:RemoveGameTimer(self.ReportCharacterStateTimer)
      self.ReportCharacterStateTimer = nil
    end
  end
  GameplayData.UnbindPlayerCharacter(self.Object)
  if Client then
    local AvatarExceptionSubsystem = SubsystemMgr:Get("AvatarExceptionSubsystem")
    if AvatarExceptionSubsystem then AvatarExceptionSubsystem:UnbindPlayerCharacter(self.Object) end
  end
  if self.PlayerKey ~= nil and self.PlayerKey > 0 then
    EventSystem:postEvent(EVENTTYPE_PLAYEREVENT_WEAPON, EVENTID_PLAYEREVENT_WEAPON_CLEAR, self.PlayerKey)
    local PlayerEventSubsystem = SubsystemMgr:Get("PlayerEventSystem")
    if PlayerEventSubsystem then PlayerEventSubsystem:ClearPlayer(self.PlayerKey) end
  end
  self:ClearFollowEmote()
  if not self:HasAuthority() then self:ClearAkEventSound() end
  self._SuperData = nil
  if Client and self._BloodSpotDelegateHandles then
    for sName, Info in pairs(self._BloodSpotDelegateHandles) do
      if type(Info) == "table" then
        local Provider = Info.Provider
        local Handle = Info.Handle
        if Handle then
          if slua.isValid(Provider) then
            local EventDelegate = Provider.AsyncLoadParticleComponentDone
            if slua.isValid(EventDelegate) and EventDelegate.Remove then
              EventDelegate:Remove(Handle)
            else
              slua.removeDelegate(Handle)
            end
          else
            slua.removeDelegate(Handle)
          end
        end
      end
      self._BloodSpotDelegateHandles[sName] = nil
    end
    self._BloodSpotDelegateHandles = nil
  end
  CharacterBase.__super.ReceiveEndPlay(self, nDeltaSeconds)
end

function CharacterBase:GetVehicleParachuteComponent()
  if self.VehicleParachuteComponent == nil then
    local ComponentClass = import("VehicleParachuteComponent")
    self.VehicleParachuteComponent = self:GetComponentByClass(ComponentClass)
  end
  return self.VehicleParachuteComponent
end

function CharacterBase:ReceivePossessed(InController)
  if not slua.isValid(InController) then return end
  self.Super:ReceivePossessed(InController)
  local FeatureUtil = require("GameLua.Mod.BaseMod.GamePlay.Feature.Common.FeatureUtil")
  FeatureUtil.ForEachFeatureCall(self, "ReceivePossessed", InController)
  self:HandleUseGlide(InController)
  self:HandleParachuteComponent(InController)
  self:InitRevivalCount(InController)
  if not Client and not Game:IsAIController(InController) then
    self:RegistAttrModifyRecordList()
  elseif not Client and Game:IsAIController(InController) then
    self.IndoorCheckTime = 2
  end
  local bBatchMove = USTExtraBlueprintFunctionLibrary.IsActorRepMovementWithBatch(self.Object)
  self:RefreshNetUpdateFrequency(bBatchMove)
  if InController and slua.isValid(InController) and InController.RefreshNetUpdateFrequency then
    InController:RefreshNetUpdateFrequency(bBatchMove)
  end
end

function CharacterBase:HandleParachuteComponent(InController)
  if slua.isValid(InController) and slua.isValid(self.ParachuteComponent) then
    if Game:IsClassOf(InController, ASTExtraPlayerController) then
      self.ParachuteComponent:InitParachuteData(InController)
    elseif Game:IsClassOf(InController, ANewFakePlayerAIController) and self.ParachuteComponent.InitAIParachuteData then
      self.ParachuteComponent:InitAIParachuteData(InController)
    end
  end
end

function CharacterBase:InitRevivalCount(InController)
  if not self:HasAuthority() then return end
  local uPlayerState = self:GetPlayerStateSafety()
  if uPlayerState and slua.isValid(uPlayerState) then
    if uPlayerState.InitRevivalCountImpl then
      uPlayerState:InitRevivalCountImpl(InController, self.Object)
    end
  end
end

function CharacterBase:HandleUseGlide(InController)
  if self:HasAuthority() then self:InitParachutingVehicle() end
end

function CharacterBase:HandleEnterGameModeFightingState()
  if slua.isValid(CGameState) and CGameState:IsCreativeMode() then return end
  if self:CharacterIsRecycled() then return end
  if slua.isValid(self.Object) and not self:HasAuthority() and self.EmoteBPIDToAnimHandleMap then
    local CheckTable = { 2206015, 2206016, 2206017, 2206018 }
    for _, ID in pairs(CheckTable) do
      local EmoteHandle = self.EmoteBPIDToAnimHandleMap:Get(ID)
      if slua.isValid(EmoteHandle) and EmoteHandle.EmoteActionList then
        local NeedStop = false
        for _, Action in pairs(EmoteHandle.EmoteActionList) do
          if Action:GetIsExecuting() then NeedStop = true break end
        end
        if NeedStop then self:OnPlayEmoteStop(ID) end
      end
    end
  end
end

function CharacterBase:InitParachutingVehicle()
  if self:HasAuthority() then
    if self.bEnsure then return end
    local ComponentClass = self.DynamicComponentMap:Get("ParachutingVehicle")
    if ComponentClass then
      local UScriptGameplayStatics = import("ScriptGameplayStatics")
      UScriptGameplayStatics.CreateComponent(self, ComponentClass, "ParachutingVehicle", false)
    end
  end
end

function CharacterBase:PlayerPoseChange(stLastPoseState, stNewPoseState)
  if Client and (self.IsClientPeeking and stNewPoseState == ESTEPoseState.Sprint or stNewPoseState == ESTEPoseState.CrouchSprint) then
    self:NM_ForceSetPeekState(false, false)
  end
end

function CharacterBase:HandleAttachedToVehicle(uVehicle)
  if not slua.isValid(uVehicle) then return end
  if slua.isValid(self.CharacterMovement) then self.CharacterMovement:SetBase(nil, "", true) end
  if uVehicle.ForceUseTPP then self.bIsFPPOnVehicle = false end
end

function CharacterBase:HandleDetachedFromVehicle(uLastVehicle)
  if not slua.isValid(self.Object) or not slua.isValid(uLastVehicle) then return end
  if uLastVehicle.ForceUseTPP then self.bIsFPPOnVehicle = true end
  if Client then
    local Location = self:K2_GetActorLocation()
    if Location.X > -1.0E-5 and Location.X < 1.0E-5 and -1.0E-5 < Location.Y and 1.0E-5 > Location.Y and -1.0E-5 < Location.Z and 1.0E-5 > Location.Z then
      Location = uLastVehicle:K2_GetActorLocation() + FVector(0, 0, 200)
      self:K2_SetActorLocation(Location, false, nil, true)
    end
  end
end

function CharacterBase:SwitchWeaponBySlotAfterConsume(OldWeaponSlotBeforeSkill)
  local ESurviveWeaponPropSlot = import("ESurviveWeaponPropSlot")
  if OldWeaponSlotBeforeSkill == ESurviveWeaponPropSlot.SWPS_HandProp then
    local Controller = self:GetPlayerControllerSafety()
    if not (slua.isValid(Controller) and GameLuaAPI.IsClassOf(Controller, ASTExtraPlayerController)) or not self:AllowState(EPawnState.SwitchWeapon, false) then return end
    if self:HasState(EPawnState.WebSwing) and slua.isValid(self.STCharacterMovement) then
      local ESpecialMovementType = import("ESpecialMovementType")
      local ESpiderSwingMoveState = import("ESpiderSwingMoveState")
      local SpiderSwingObj = self.STCharacterMovement:GetSpecialMoveObjBySpecialMoveType(ESpecialMovementType.SPECIAL_MOVE_SpiderSwing)
      if slua.isValid(SpiderSwingObj) then
        local nCurState = SpiderSwingObj:GetCurMoveState()
        if nCurState == ESpiderSwingMoveState.Launching or nCurState == ESpiderSwingMoveState.Swinging then return end
      end
    end
    Controller:ServerAutoSwitchSameSlotWeapon(OldWeaponSlotBeforeSkill)
  else
    self:SwitchWeaponBySlot(OldWeaponSlotBeforeSkill, true, false, false)
  end
end

function CharacterBase:IsEnablePlayerShovleing()
  return not self:HasState(EPawnState.Prone) and self:HasState(EPawnState.Sprint)
end

function CharacterBase:OnRep_CarryBackStateChanged()
  local uCarryBackComp = self:GetCarryBackComp()
  if slua.isValid(uCarryBackComp) then uCarryBackComp:OnRep_CarryBackStateChanged() end
end

function CharacterBase:ShowCharacter(bShow) self:SetActorHiddenInGame(not bShow) end

function CharacterBase:ShowMainWeaponOnBack(bShow)
  local uWeaponMgrCom = self:GetWeaponManager()
  if uWeaponMgrCom and slua.isValid(uWeaponMgrCom) then uWeaponMgrCom.ShowMainWeaponModelOnBack = bShow end
end

function CharacterBase:AddRevivalCount(nRevivalCount)
  if type(nRevivalCount) == "number" then
    local uPlayerState = self:GetPlayerStateSafety()
    if uPlayerState and slua.isValid(uPlayerState) then
      if uPlayerState.GetRevivalCount and uPlayerState.SetRevivalCount then
        local GeneralRevivalCount = uPlayerState:GetRevivalCount() + nRevivalCount
        if GeneralRevivalCount < 0 then GeneralRevivalCount = 0 end
        uPlayerState:SetRevivalCount(GeneralRevivalCount)
      end
    end
  end
end

function CharacterBase:SetUseDeadBox(bUseDeadBox)
  local eUseDeadBox = 1
  if not bUseDeadBox then eUseDeadBox = 0 end
  self:SetAttrValue("bUseDeadBox", eUseDeadBox, -1)
end

function CharacterBase:GetUseDeadBox()
  local nUseDeadBox = math.floor(self:GetAttrValue("bUseDeadBox") + 0.1)
  return 0 < nUseDeadBox
end

function CharacterBase:CharacterAttrChangeEvent(uPawn, AttrName, AttrVal)
  if self.Object == uPawn then
    if AttrName == "bUseDeadBox" then
      self.bIsUseDeadBox = self:GetUseDeadBox()
    elseif AttrName == "IsInUnderGroundArea" then
      self.bIsInUnderGroundArea = AttrVal == 1
      if not Client then
        local ESightVisionCondition = import("ESightVisionCondition")
        local USTExtraModLogicSwitchLibrary = import("STExtraModLogicSwitchLibrary")
        if USTExtraModLogicSwitchLibrary.IsNightVisionUnderGroundOnly() then
          self:SetSightCondition(self.bIsInUnderGroundArea, ESightVisionCondition.NightVisionUnderGround)
        end
      end
    elseif AttrName == "IsAroundUndergroundEntry" then
      self.bIsAroundUndergroundEntry = AttrVal == 1
    elseif AttrName == "EmotePlayRate" then
      if Client then
        local PhotoGrapherSubSystem = SubsystemMgr:Get("PhotoGrapherSubSystem")
        if PhotoGrapherSubSystem then PhotoGrapherSubSystem:EmotePlayRateChanged(self.Object, AttrVal) end
      end
    elseif AttrName == "AreaID" then
      self:ChangeFootStepValue(AttrVal)
      self:HandleAreaIDChanged(AttrVal)
      EventSystem:postEvent(EVENTTYPE_PLAYEREVENT_CHARACTER, EVENTID_PLAYEREVENT_LOCAL_CHAR_AREA_ID_CHANGED, AttrVal)
    elseif AttrName == "MapID" then
      if not Client and self:IsAuthority() then
        local uPlayerState = self:GetPlayerStateSafety()
        if slua.isValid(uPlayerState) then uPlayerState.MapID = AttrVal end
      end
    elseif AttrName == "DanceStageAreaState" and Client then
      EventSystem:postEvent(EVENTTYPE_PLAYEREVENT_CHARACTER, EVENTID_PLAYEREVENT_DANCESTATE_CHANGED, AttrVal, self.Object)
    end
  end
end

function CharacterBase:ChangeFootStepValue(AttrVal)
  if self.DefaultFootStep and AttrVal == 0 then return end
  local FootStepSoundConfig = GamePlayTools.GetCurrentConfig("FootStepSoundConfig")
  if not FootStepSoundConfig or not FootStepSoundConfig.bOpenAreaFootStep then return end
  local IntVal = math.tointeger(AttrVal)
  local AreaPara = FootStepSoundConfig[IntVal] or FootStepSoundConfig.DefaultPara
  local DefaultPara = FootStepSoundConfig.DefaultPara
  self.DefaultFootStep = AreaPara == DefaultPara
  self.FloorHeight = AreaPara.FloorHeight or DefaultPara.FloorHeight
  self.GFloorValue = AreaPara.GFloorValue or DefaultPara.GFloorValue
  self.DiffFloorValue = AreaPara.DiffFloorValue or DefaultPara.DiffFloorValue
  self.bInSoundDiffFloorArea = AreaPara.bInSoundDiffFloorArea or DefaultPara.bInSoundDiffFloorArea
end

function CharacterBase:HandleAreaIDChanged(AttrVal) end

function CharacterBase:HandleOnRespawn()
  if self:IsAuthority() then
    EventSystem:postEvent(EVENTTYPE_SECURITY, EVENTID_SECURITY_PLAYER_RESPAWN, self.Object)
  else
    local ENetRole = import("ENetRole")
    local uPlayerController = self:GetPlayerControllerSafety()
    if self:IsAutonomousProxy() then
      local UGameplayStatics = import("GameplayStatics")
      local uGameInstance = UGameplayStatics.GetGameInstance(self)
      if slua.isValid(uGameInstance) then
        local uReplay = uGameInstance:GetClientInGameReplay()
        if slua.isValid(uReplay) and uReplay:IsInRecordState() then uReplay:OnPlayerRespawnNotify() end
      end
      local VibrateUtilitySubsystem = SubsystemMgr:Get("VibrateUtilitySubsystem")
      if VibrateUtilitySubsystem and VibrateUtilitySubsystem.HandleCharacterRespawned then
        VibrateUtilitySubsystem:HandleCharacterRespawned()
      end
      if slua.isValid(uPlayerController) and not uPlayerController:IsPureSpectator() and not uPlayerController:IsDemoPlayGlobalObserver() and not uPlayerController:IsDemoPlaySpectator() then
        uPlayerController:QuitSpectating()
        local uViewTarget = uPlayerController:GetViewTarget()
        if slua.isValid(uViewTarget) and slua.isValid(self.Object) then
          if uViewTarget.Role == ENetRole.ROLE_SimulatedProxy then
            uPlayerController:SetViewTargetTest(self.Object)
          elseif Game:IsClassOf(uViewTarget, slua.loadClass("/Game/Mod/EvoBase/Arts_PlayerBluePrints/Skill/CarryDeadBox/DeadBoxViewTarget.DeadBoxViewTarget")) then
            uPlayerController:SetViewTargetTest(self.Object)
          end
        end
        if uPlayerController:ShouldForceFPPView(self) then
          local EPlayerCameraMode = import("EPlayerCameraMode")
          uPlayerController:SwitchCameraMode(EPlayerCameraMode.PCM_FPP, nil, false, true)
        else
          uPlayerController:SwitchCameraMode(uPlayerController.CurCameraMode, nil, false, true)
        end
      end
      self:AddGameTimer(3, false, function()
        local PlayerRespawnData = slua.IndexReference(self, "PlayerRespawnData")
        if PlayerRespawnData and not PlayerRespawnData.bIsDead and self.CharacterHide and not self.CharacterHide.bCharacterHideIngame and self.bHidden == true and not self:HasState(EPawnState.InPlane) then
          self:SetActorHiddenInGame(false)
        end
      end)
    elseif slua.isValid(self.STCharacterMovement) then
      self.STCharacterMovement.MaxWalkSpeed = 600
    end
    if slua.isValid(uPlayerController) and uPlayerController:IsInSpectating() and uPlayerController:GetLastestViewPlayerKey() == self.PlayerKey then
      uPlayerController:ServerObserveCharacter(self.PlayerKey)
    end
    if slua.isValid(self.STCharacterMovement) then
      self.STCharacterMovement.GravityScale = 1.0
      local uAttachParentActor = self:GetAttachParentActor()
      if slua.isValid(uAttachParentActor) then
        self:CheckAttachedOrDetachedVehicle(true)
        self.STCharacterMovement:Deactivate()
      end
    end
    if self.Role == ENetRole.ROLE_SimulatedProxy then self:RefreshThermalImagingLocal() end
  end
  self:LuaBroadcastCommonEventCpp("EVENTTYPE_PLAYEREVENT_CHARACTER", "EVENTID_PLAYEREVENT_REVIVAL", self.PlayerKey, self.Object, self.TeamID)
end

function CharacterBase:HandleOnPreEnterNearDeath(uKillPlayerController, DamageCauser)
  EventSystem:postEvent(EVENTTYPE_INGAME_NORMAL, EVENTID_ON_PRE_ENTER_NEAR_DEATH, self)
  if CGameMode and CGameMode.CheckTeammateAllNearDeath then CGameMode:CheckTeammateAllNearDeath(self.Object) end
end

function CharacterBase:LuaHandleParachuteStateChanged(LastParachuteState, NewParachuteState)
  local EParachuteState = import("EParachuteState")
  if not Client then
    if NewParachuteState == EParachuteState.PS_FreeFall or NewParachuteState == EParachuteState.PS_Opening then
      self:SetNetCullDistanceSquared(900000000)
    else
      self:SetNetCullDistanceSquared(self.DefaultNetCullDistanceSq)
    end
  else
    local ENetRole = import("ENetRole")
    if self.Role == ENetRole.ROLE_AutonomousProxy then
      if (NewParachuteState == EParachuteState.PS_FreeFall or NewParachuteState == EParachuteState.PS_Opening) and self.SwimComponet and slua.isValid(self.SwimComponet) then
        self.SwimComponet:LeaveWater()
      end
      if self.Role == ENetRole.ROLE_AutonomousProxy and self.HealthStatus == ECharacterHealthStatus.HasLastBreath and (self.ParachuteState == EParachuteState.PS_Opening or self.ParachuteState == EParachuteState.PS_FreeFall) then
        self:SwitchCameraToParachuteOpening()
      end
      if self.HealthStatus == ECharacterHealthStatus.HasLastBreath and LastParachuteState == EParachuteState.PS_Opening and (NewParachuteState ~= EParachuteState.PS_Opening or NewParachuteState ~= EParachuteState.PS_Landing) then
        local uSpringArmComp = self.SpringArmComp
        if slua.isValid(uSpringArmComp) then
          local CrouchHalfHeight = self:GetCrouchHalfHeight() or 60
          uSpringArmComp:K2_SetRelativeLocation(FVector(0, 0, -CrouchHalfHeight), false, nil, true)
          local ECameraDataType = import("ECameraDataType")
          uSpringArmComp:SetCameraDataEnable(ECameraDataType.ECameraDataType_NearDeath, true)
        end
      end
      EventSystem:postEvent(EVENTTYPE_INGAME_PARACHUTING, EVENTID_CLIENT_PARACHUTE_STATE_CHANGE, LastParachuteState, NewParachuteState)
    end
  end
  if NewParachuteState == EParachuteState.PS_None then
    EventSystem:postEvent(EVENTTYPE_INGAME_PARACHUTING, EVENTID_PARACHUTING_END, self.Object)
  end
end

function CharacterBase:LuaHandleRepParachuteStateDelegate()
  local ENetRole = import("ENetRole")
  local EParachuteState = import("EParachuteState")
  if not (self and self.Role) or not self.ParachuteState then return end
  if self.Role == ENetRole.ROLE_SimulatedProxy and self.ParachuteState == EParachuteState.PS_FreeFall then
    if self.RefreshParacthueAnimTimer then
      self:RemoveGameTimer(self.RefreshParacthueAnimTimer)
      self.RefreshParacthueAnimTimer = nil
    end
    self.RefreshParacthueAnimTimer = self:AddGameTimer(0.5, false, function()
      self:RemoveGameTimer(self.RefreshParacthueAnimTimer)
      self.RefreshParacthueAnimTimer = nil
      if self and slua.isValid(self.Object) then self:TryCacheParachuteAnim() end
    end)
  end
end

function CharacterBase:TryCacheParachuteAnim()
  local uCharacter = self.Object
  if not slua.isValid(uCharacter) or not slua.isValid(uCharacter.Mesh) then return end
  local CH_ABP_Parachute_Class = slua.loadClass("/Game/Arts_Player/Characters/Animation/Base_AnimBP/Feature/CH_ABP_Parachute.CH_ABP_Parachute")
  local uAnimInstances = uCharacter.Mesh:GetSubAnimInstances()
  if uAnimInstances and uAnimInstances.Num then
    local num = uAnimInstances:Num()
    for i = 1, num do
      local uAnimInst = uAnimInstances:Get(i - 1)
      if slua.isValid(uAnimInst) and Game:IsClassOf(uAnimInst, CH_ABP_Parachute_Class) and uAnimInst.CacheParachuteAnimVars ~= nil then
        uAnimInst:CacheParachuteAnimVars(true)
        break
      end
    end
  end
end

function CharacterBase:GetBroadcastFatalDamageExpandData(uCauserPawn, uVictimPawn, RealKiller, DamageType, CauserWeaponAvatarID)
  local expandDataTable = self:GetBroadcastFatalDamageExpandDataForLua(uCauserPawn, uVictimPawn)
  if SubsystemMgr then
    local FatalDamageExpandDataSubsystem = SubsystemMgr:Get("FatalDamageExpandDataSubsystem")
    if FatalDamageExpandDataSubsystem then
      expandDataTable = FatalDamageExpandDataSubsystem:GetBroadcastFatalDamageExpandData(uCauserPawn, uVictimPawn, expandDataTable, RealKiller, DamageType)
    end
  end
  expandDataTable = expandDataTable or {}
  expandDataTable.CauserWeaponAvatarID = CauserWeaponAvatarID or 0
  local expandDataStr = slua.LuaArchiverEncode(LuaStateWrapper, expandDataTable)
  import("/Script/ShadowTrackerExtra.STExtraBaseCharacter").SetExpandDataContent(expandDataStr)
  return expandDataStr
end

function CharacterBase:GetBroadcastFatalDamageExpandDataForLua(uCauserPawn, uVictimPawn)
  local expandDataTable = {}
  if uVictimPawn and slua.isValid(uVictimPawn) then
    expandDataTable.bHaveSelfRescueItem = false
    local PlayerState = uVictimPawn:GetPlayerStateSafety()
    if PlayerState and slua.isValid(PlayerState) then
      if PlayerState.CheckCanSelfRescue then PlayerState:CheckCanSelfRescue() end
    end
    if 0 < uVictimPawn:GetAttrValue("bCanSelfRescue") then expandDataTable.bHaveSelfRescueItem = true end
  end
  return expandDataTable
end

function CharacterBase:ServerCheckEmoteCanPlay(EmoteID)
  if not self:CheckEmoteBanTable(EmoteID) then return false end
  local logic_emote = require("GameLua.Mod.Library.GamePlay.Avatar.Emote.logic_emote")
  if logic_emote.CheckIsDanceTogetherEmote(EmoteID) then
    local EmoteSubSystem = SubsystemMgr:Get("EmoteSubSystem")
    if not EmoteSubSystem:IsInPreListOrDanceList(self.Object) then return false end
  end
  return true
end

function CharacterBase:UpdateEmoteExtraInfo(EmoteID, ExtraInfo)
  if EmoteID == 12220605 then
    math.randomseed(os.time())
    return tostring(math.random(0, 99))
  end
  return ExtraInfo
end

function CharacterBase:CheckEmoteBanTable(EmoteID)
  local EmoteData = CDataTable.GetTableData("BattleBanOnEmote", EmoteID)
  if not EmoteData then return true end
  local uGameState = GameplayData.GetGameState()
  if not slua.isValid(uGameState) or not uGameState.GetGameModeState then return true end
  if uGameState:GetGameModeState() ~= "ReadyState" then return false end
  return true
end

function CharacterBase:ReportExceptionOnVehicle(Type, Msg)
  local ErrorMsg = string.format("VehicleException Type:%s, Msg:%s\n", Type, Msg)
  if Client then
    local ClientToolsReport = require("client.slua.logic.report.ClientToolsReport")
    ClientToolsReport:SendReport(ClientToolsReport.Enum_SvrReport_Type.Enum_Vehicle, ErrorMsg)
  end
  if LogExceptionAndReport ~= nil then LogExceptionAndReport(ErrorMsg) end
end

function CharacterBase:PlayLevelSequenceByPath(SequenceActorPath, LevelSequencePath, TimeOffset)
  return self:PlayLevelSequenceInternal(SequenceActorPath, LevelSequencePath, nil, TimeOffset)
end

function CharacterBase:PlayLevelSequenceByPathAndBindingInfo(SequenceActorPath, LevelSequencePath, TrackBindingInfo, TimeOffset)
  return self:PlayLevelSequenceInternal(SequenceActorPath, LevelSequencePath, TrackBindingInfo, TimeOffset)
end

function CharacterBase:PlayLevelSequenceInternal(SequenceActorPath, LevelSequencePath, TrackBindingInfo, TimeOffset)
  if TimeOffset == nil then TimeOffset = 0 end
  if self.CurrentLevelSequence then self:StopCurrentLevelSequence() end
  local SequenceTransform = FTransform()
  SequenceTransform:SetLocation(self:K2_GetActorLocation())
  local LevelSeqActor = Game:PlayLevelSequence(self, LevelSequencePath, SequenceTransform, SequenceActorPath, false)
  if not slua.isValid(LevelSeqActor) then return false end
  LevelSeqActor:SetOwner(self)
  if LevelSeqActor.SetMetaData then LevelSeqActor:SetMetaData(TrackBindingInfo, TimeOffset) end
  self.CurrentLevelSequence = LevelSeqActor
  return true
end

function CharacterBase:StopCurrentLevelSequence()
  if self.CurrentLevelSequence then
    if slua.isValid(self.CurrentLevelSequence) then
      self.CurrentLevelSequence:StopMontageParticle("DirectorSequence")
      self.CurrentLevelSequence:K2_DestroyActor()
    end
    self.CurrentLevelSequence = nil
  end
end

function CharacterBase:GetCurrentLevelSequenceActor()
  if not slua.isValid(self.CurrentLevelSequence) then return nil end
  return self.CurrentLevelSequence
end

function CharacterBase:OnLevelSequenceStop(StopType)
  if self.CurrentLevelSequence then self.CurrentLevelSequence = nil end
end

function CharacterBase:HandleCharacterFallingModeChange(bFalling)
  if bFalling then return end
  if not slua.isValid(self.Object) then return end
  local uSkillManager = self:GetSkillManager()
  if not slua.isValid(uSkillManager) then return end
  if slua.isValid(self.Object) then
    self:AddGameTimer(0.05, false, function()
      if self.GetCurSkill then
        local uCurSkill = self:GetCurSkill()
        if slua.isValid(uCurSkill) and uSkillManager:IsCastingSkillID(1000001) and uSkillManager:GetSkillCurPhase(uCurSkill) == 1 then
          local UGameplayStatics = import("GameplayStatics")
          local CurTime = UGameplayStatics.GetRealTimeSeconds(CGameWorld)
          if CurTime.LastPlayFallSoundTime > 0.7 then self:PlayFootstepSound(4) end
        end
      end
    end)
  end
end

function CharacterBase:PlayFootstepSound(eFootStepState)
  self.Super:PlayFootstepSound(eFootStepState)
  if not Client then return end
  EventSystem:postEvent(EVENTTYPE_PLAYEREVENT_CHARACTER, EVENTTYPE_PLAYEREVENT_CHARACTER_FOOTSTEP_SOUND, self.Object)
end

function CharacterBase:OnRep_bCableCarView() self:SwitchFreeView(self.bCableCarView) end

function CharacterBase:SwitchFreeView(bEnable)
  if not slua.isValid(self.Object) then return end
  local uSpringArmComp = self.SpringArmComp
  if bEnable then
    self.bFreeView = true
    self.bUseControllerRotationYaw = false
    if slua.isValid(uSpringArmComp) then
      uSpringArmComp.bForceUseTargetArmLength = true
      uSpringArmComp.TargetArmLength = 890
    end
  else
    self.bFreeView = false
    self.bUseControllerRotationYaw = true
    if slua.isValid(uSpringArmComp) then
      uSpringArmComp.bForceUseTargetArmLength = false
      uSpringArmComp.TargetArmLength = 220
    end
  end
end

function CharacterBase:IsEnableFollowPlayEmote() return LobbySystem.CheckOpen(BP_ENUM_DANCE_FOLLOW_SWITCH) end

function CharacterBase:IsInteractiveExpression(EmoteID)
  local ItemCfg = CDataTable.GetTableData("Item", EmoteID)
  if ItemCfg and ItemCfg.ItemSubType == 2205 then return true end
  return false
end

function CharacterBase:CheckCanFollowPlayEmote(EmoteId)
  if not EmoteId or EmoteId == 0 then return false end
  local FollowEmoteCfg = CDataTable.GetTableData("FollowEmoteCfg", EmoteId)
  if FollowEmoteCfg and FollowEmoteCfg.CanPlay == 0 then
    local TipsID = FollowEmoteCfg.TipsID and FollowEmoteCfg.TipsID ~= 0 and FollowEmoteCfg.TipsID or 44697
    local uPlayerController = self:GetPlayerControllerSafety()
    if slua.isValid(uPlayerController) then uPlayerController:DisplayGameTipWithMsgID(TipsID) end
    return false
  end
  if self:IsInteractiveExpression(EmoteId) then
    local uPlayerController = self:GetPlayerControllerSafety()
    if slua.isValid(uPlayerController) then uPlayerController:DisplayGameTipWithMsgID(44697) end
    return false
  end
  local logic_emote = require("GameLua.Mod.Library.GamePlay.Avatar.Emote.logic_emote")
  if logic_emote.IsMileStoneEmote(EmoteId) then return false end
  if logic_emote.IsCustomWeaponShow(EmoteId) then return false end
  return true
end

function CharacterBase:ClearFollowEmote()
  if self:IsAutonomousProxy() then
    if self.GetPlayerControllerSafety then
      local Controller = self:GetPlayerControllerSafety()
      if slua.isValid(Controller) then Controller.OnShowFollowEmoteDelegate:BroadCast(false) end
    end
  end
  if self.ClearEmotePlayer then self:ClearEmotePlayer() end
end

function CharacterBase:ClearAkEventSound()
  local UAkGameplayStatics = import("AkGameplayStatics")
  local EAttachLocation = import("EAttachLocation")
  local Location = FVector(0, 0, 0)
  if slua.isValid(self.RootComponent) and EAttachLocation and Location then
    local uAkComponent = UAkGameplayStatics.GetAkComponent(self.RootComponent, "", Location, EAttachLocation.KeepRelativeOffset)
    if slua.isValid(uAkComponent) then uAkComponent:Stop() end
  end
end

function CharacterBase:ShowEffectAfterSelfRescueSucceed() end

function CharacterBase:ServerShowShowUIConfigUI(uiConfigName)
  if not Client then return end
  local ENetRole = import("ENetRole")
  if UIManager.UI_Config_InGame[uiConfigName] and (self:IsLocalControlorView() or self:IsLocalViewed() or self.Role == ENetRole.ROLE_AutonomousProxy) then
    UIManager.ShowUI(UIManager.UI_Config_InGame[uiConfigName])
  end
end

function CharacterBase:ClientRPC_FailedToJoinDance(Reason) ShowNotice(Reason) end

function CharacterBase:ClientRPC_TryJoinDance(DanceActor, Index)
  if not slua.isValid(DanceActor) then return end
  DanceActor:ClientTryJoinDance(self.Object, Index)
end

function CharacterBase:ClientRPC_ShowEffectAfterFruitBingo(ShakingAudioPath, SurpriseAudioPath, SurpriseTipsID)
  if SurpriseTipsID and 0 < SurpriseTipsID then IngameTipsTools.BattleGeneralTip(SurpriseTipsID) end
  local audio_util = require("client.common.audio_util")
  if ShakingAudioPath and ShakingAudioPath ~= "" then audio_util.PlayAudioByActorAsync(ShakingAudioPath, self.Object) end
  if SurpriseAudioPath and SurpriseAudioPath ~= "" then audio_util.PlayAudioByActorAsync(SurpriseAudioPath, self.Object) end
end

function CharacterBase:ClientRPC_PlayMontageCamera(LookAtLocation, Radius, Time, CallbackName)
  local MontageCameraSubsystem = SubsystemMgr:Get("MontageCameraSubsystem")
  if MontageCameraSubsystem then
    if CallbackName and CallbackName ~= "" and self[CallbackName] and type(self[CallbackName]) == "function" then
      MontageCameraSubsystem:Play(LookAtLocation, Radius, Time, self[CallbackName])
    else
      MontageCameraSubsystem:Play(LookAtLocation, Radius, Time)
    end
  end
end

function CharacterBase:OnPlayMontageCameraCallback() end

function CharacterBase:ServerRPC_FailPreJoinDance(DanceActor)
  if not slua.isValid(DanceActor) then return end
  DanceActor:ServerFailPreJoinDance(self.Object)
end

function CharacterBase:CheckEmoteNeedUseReliableRPC(EmoteIndex)
  local Controller = self:GetPlayerControllerSafety()
  if slua.isValid(Controller) and Controller.PlayEmoteFeature and Controller.PlayEmoteFeature:CheckNeedReliable(EmoteIndex) then return true end
  return false
end

function CharacterBase:RegisteAirControlResumEvent(OldAirControl)
  self:AddControlEvent(self, "OnMovementBaseChanged", function(_, Character, NewMovementBase, OldMovementBase)
    if not slua.isValid(NewMovementBase) then return end
    local CharacterMovement = self.STCharacterMovement
    if not slua.isValid(CharacterMovement) then return end
    CharacterMovement.AirControl = OldAirControl
    self:RemoveControlEvent(self, "OnMovementBaseChanged")
  end, self)
end

function CharacterBase:ReplaceGrenadeSkills()
  local SkillReplaceConfig = GamePlayTools.GetCurrentConfig("SkillReplaceConfig")
  local uSkillMgr = self:GetSkillManager()
  if slua.isValid(uSkillMgr) and SkillReplaceConfig and SkillReplaceConfig.ReplaceSkill then
    for sourceSkill, NewSkill in pairs(SkillReplaceConfig.ReplaceSkill) do
      uSkillMgr:ReplaceSkill(sourceSkill, NewSkill)
    end
  end
end

function CharacterBase:GetGrenadeKillBindGunIDByPC(KillerPC, GrenadeID)
  if Client then return 0 end
  if not slua.isValid(KillerPC) then return 0 end
  local ExtendAttribute = require("Server.config.ExtendAttribute")
  local PlayerDataMgr = require("Server.Data.ServerPlayerDataMgr")
  local GrenadeBindInfo = PlayerDataMgr.GetPlayerProgressFromServer(KillerPC.UID, ExtendAttribute.GrenadeBindWeaponMap)
  if not GrenadeBindInfo then return 0 end
  if GrenadeBindInfo[GrenadeID] ~= nil then return GrenadeBindInfo[GrenadeID] end
  return 0
end

function CharacterBase:CheckIsValidXSuitBornIslandAction(EmoteID)
  local XSuitUtil = require("GameLua.Activity.Commercialize.GamePlay.XSuit.XSuitUtil")
  local uPlayerController = self:GetPlayerControllerSafety()
  if not slua.isValid(uPlayerController) or not uPlayerController.CommerFeature then return false end
  local uAvatarComp2 = self:getAvatarComponent2()
  if not slua.isValid(uAvatarComp2) then return false end
  local AvatarItem = uAvatarComp2:GetEquippedItemDefineID(EAvatarSlotType.EAvatarSlotType_ClothesEquipemtSlot)
  if XSuitUtil:GetBornIslandActionByItemID(AvatarItem.TypeSpecificID, uAvatarComp2) ~= EmoteID then return false end
  local Period = XSuitUtil:GetPeriodByBattleActionID(EmoteID)
  if Period and 0 < Period then
    local UnLockLevel = XSuitUtil:GetUnLockLevelByFeature(AvatarItem.TypeSpecificID, Period, uPlayerController.CommerFeature.XSuitUnlockLevelList)
    if not XSuitUtil:IsValidBornIslandAction(EmoteID, UnLockLevel) then return false end
  end
  return true
end

function CharacterBase:CheckIsValidEmoteIDBP(EmoteID)
  local IsValid = false
  local Controller = self:GetPlayerControllerSafety()
  if slua.isValid(Controller) and Controller.PlayEmoteFeature then
    IsValid = Controller.PlayEmoteFeature:CheckIsValidEmoteIDBP(EmoteID)
  end
  if not IsValid and self.CoopEmoteCharFeature then
    IsValid = self.CoopEmoteCharFeature:CheckIsValidEmoteIDBP(EmoteID)
  end
  return IsValid
end

function CharacterBase:IsCoopEmote(EmoteId, CoopPhase)
  if self.CoopEmoteCharFeature then return self.CoopEmoteCharFeature:IsCoopEmote(EmoteId, CoopPhase) end
  return false
end

function CharacterBase:ShouldCheckCoopEmote()
  if self.CoopEmoteCharFeature then return self.CoopEmoteCharFeature:ShouldCheckCoopEmote() end
  return false
end

function CharacterBase:ShouldShowCoopEmoteBtn(EmotePlayer)
  if self.CoopEmoteCharFeature then return self.CoopEmoteCharFeature:ShouldShowCoopEmoteBtn(EmotePlayer) end
  return false
end

function CharacterBase:RPC_Client_OnCoopEmotePhaseChange(CoopPhase)
  if self.CoopEmoteCharFeature then self.CoopEmoteCharFeature:HandleClientOnCoopEmotePhaseChange(CoopPhase) end
end

function CharacterBase:RPC_Server_JoinCoopEmote(EmotePlayer)
  local CasterPlayerKey = EmotePlayer.PlayerKey
  if not CasterPlayerKey then return end
  local CoopEmoteSubSystem = SubsystemMgr:Get("CoopEmoteSubSystem")
  if not CoopEmoteSubSystem:HasCaster(CasterPlayerKey) then return end
  self.Super:RPC_Server_JoinCoopEmote(EmotePlayer)
end

function CharacterBase:ServerOnCoopEmotePhaseChange(CoopPhase)
  if self.CoopEmoteCharFeature then self.CoopEmoteCharFeature:HandleServerOnCoopEmotePhaseChange(CoopPhase) end
end

function CharacterBase:CheckInPhotoGrapherMode()
  local PhotoGrapherSubSystem = SubsystemMgr:Get("PhotoGrapherSubSystem")
  if PhotoGrapherSubSystem and PhotoGrapherSubSystem.bIsPhotoGrapherMode then return true end
  return false
end

function CharacterBase:ReportCharacterState()
  if not slua.isValid(self.Object) then return end
  local uPlayerController = self:GetPlayerControllerSafety()
  if not slua.isValid(uPlayerController) then return end
  if uPlayerController.ReportCharacterStateData then uPlayerController:ReportCharacterStateData() end
end

function CharacterBase:ParseServiceDebugInfo(BasicInfoKeys, DetailInfoKeys)
  if BasicInfoKeys == nil then return end
  local StringUtil = require("common.string_util")
  local InfoMap = {}
  local SpeedStr = string.format("%.3f/%.3f", self:GetVelocity():Size(), self.CharacterMovement.MaxWalkSpeed)
  local PlayerStates = ""
  for i = 0, EPawnState.__MAX do
    if self:HasState(i) then PlayerStates = PlayerStates .. tostring(i) .. "," end
  end
  if BasicInfoKeys and BasicInfoKeys:Num() < 3 then
    local AIDebugInfoConfig = require("GameLua.Mod.BaseMod.DS.AI.AIDebugInfoConfig")
    if AIDebugInfoConfig and AIDebugInfoConfig[2] then
      for _, KeysStr in pairs(AIDebugInfoConfig[2]) do BasicInfoKeys:Add(KeysStr) end
    end
  end
  InfoMap.Level = tostring(self.EnsureLevel)
  InfoMap.Key = tostring(self:GetPlayerKey())
  InfoMap.TeamID = tostring(self.TeamID)
  InfoMap.HP = string.format("%d/%d", math.floor(self.Health), math.floor(self.HealthMax))
  InfoMap.NearDeathBreath = string.format("%.2f", self.NearDeathBreath)
  InfoMap.FreeCamera = tostring(self.SimulateViewData.FreeCamera)
  InfoMap.Speed = SpeedStr
  InfoMap.State = PlayerStates
  InfoMap.Location = self:K2_GetActorLocation():ToString()
  InfoMap.Rotation = self:K2_GetActorRotation():ToString()
  InfoMap.MLAIStyle = tostring(self.MLEnsureStyle)
  InfoMap.TeamInstantiated = tostring(self.TeamInstantiated)
  if self.TeleportID then InfoMap.TeleportID = tostring(self.TeleportID) end
  if self.TargetUID_Debug then InfoMap.Target = tostring(self.TargetUID_Debug) end
  local uPlayerController = GameplayData.GetPlayerController()
  if uPlayerController and slua.isValid(uPlayerController) and slua.isValid(self.Object) then
    local ViewTarget = uPlayerController:GetViewTarget()
    if ViewTarget and slua.isValid(ViewTarget) then
      InfoMap.Distance = string.format("%.0f", Game:GetActorDistance(self.Object, ViewTarget) / 100)
    end
  end
  if self.DebugAIInfoTable then
    for InfoKey, InfoValue in pairs(self.DebugAIInfoTable) do InfoMap[InfoKey] = InfoValue end
  end
  local bHaveEnsureStyle = false
  local DebugInfoArray = StringUtil.Split(self.BehaviorServiceDebugInfo, ";")
  local ExtraInfo = ""
  for index, InfoStr in ipairs(DebugInfoArray) do
    local InfoSplit = StringUtil.Split(InfoStr, "=")
    if not InfoSplit or not InfoSplit[2] then
      ExtraInfo = ExtraInfo .. InfoStr .. "\n"
    elseif Game:Contains(DetailInfoKeys, InfoSplit[1]) and string.find(InfoSplit[2], "=") then
      local InfoSplit2 = StringUtil.Split(InfoSplit[2], "=")
      DetailInfoKeys:Add(InfoSplit2[1])
      InfoMap[InfoSplit2[1]] = InfoSplit2[2]
    else
      InfoMap[InfoSplit[1]] = InfoSplit[2]
      if InfoSplit[1] == "EnsureStyle" then
        self.EnsureStyle = tonumber(InfoSplit[2])
        bHaveEnsureStyle = true
      end
      if bHaveEnsureStyle == false and self.EnsureStyle > 0 and InfoSplit[1] == "ResID" then
        self.EnsureStyle = 0
      end
    end
  end
  local AIType = "CommonAI"
  if self.EnsureStyle == 4 then AIType = "CommonAI_Advance"
  elseif self.EnsureStyle == 1 then AIType = "MLAI"
  elseif self.EnsureStyle == 2 then AIType = "MLAI_Delivery"
  elseif self.EnsureStyle == 3 then AIType = "MLAI_Teammate"
  elseif self.EnsureStyle == 5 then AIType = "MLAI_Humanoid" end
  InfoMap.Type = AIType
  self.ServiceDebugInfoForShow = ""
  local FinnalStr = ""
  local TempStr = ""
  for index, Keys in pairs(BasicInfoKeys) do
    local KeysArr = StringUtil.Split(Keys, ";")
    local EmptyLine = true
    for _, Key in ipairs(KeysArr) do
      if InfoMap[Key] then
        TempStr = string.format("[%s=%s]", Key, InfoMap[Key])
        EmptyLine = false
        FinnalStr = FinnalStr .. TempStr
      end
    end
    if not EmptyLine then FinnalStr = FinnalStr .. "\n" end
  end
  FinnalStr = FinnalStr .. "::"
  for _, Keys in pairs(DetailInfoKeys) do
    local KeysArr = StringUtil.Split(Keys, ";")
    local EmptyLine = true
    for _, Key in ipairs(KeysArr) do
      if InfoMap[Key] then
        TempStr = string.format("[%s=%s]", Key, InfoMap[Key])
        EmptyLine = false
        FinnalStr = FinnalStr .. TempStr
      end
    end
    if not EmptyLine then FinnalStr = FinnalStr .. "\n" end
  end
  FinnalStr = FinnalStr .. ExtraInfo
  self.ServiceDebugInfoForShow = FinnalStr
end

function CharacterBase:SetMLEnsureStyle(InMLStyle)
  local DebugLastMLEnsureStyle_DS = string.format("%d_%.1f", self.MLEnsureStyle, CGameState:GetServerWorldTimeSeconds())
  self:AddDebugAIInfoTable("LastMLAIStyle", DebugLastMLEnsureStyle_DS)
  self.MLEnsureStyle = InMLStyle
  self:DSSetCharacterIntPropertyForReplay("MLEnsureStyle", InMLStyle)
end

function CharacterBase:SetMLEnsureExtraInfo(InMLEnsureExtraInfo)
  self:AddDebugAIInfoTable("MLExtraInfo", InMLEnsureExtraInfo)
  self.MLEnsureExtraInfo = InMLEnsureExtraInfo
  self:DSSetCharacterStringPropertyForReplay("MLEnsureExtraInfo", InMLEnsureExtraInfo)
end

function CharacterBase:GetBodyPartOffset(nBodyPart, CurrentState, nHasWeapon, nPeekState)
  local StaticBodyOffsetData = require("GameLua.Mod.Library.GamePlay.AI.StaticBodyOffsetData")
  local OffsetData = { 0, 0, 0 }
  nHasWeapon = nHasWeapon + 1
  nPeekState = nPeekState + 1
  if StaticBodyOffsetData[CurrentState] and StaticBodyOffsetData[CurrentState][nHasWeapon] and StaticBodyOffsetData[CurrentState][nHasWeapon][nPeekState] then
    OffsetData = StaticBodyOffsetData[CurrentState][nHasWeapon][nPeekState][nBodyPart] or OffsetData
  end
  return FVector(OffsetData[1], OffsetData[2], OffsetData[3])
end

function CharacterBase:BlueprintSetServiceDebugInfo(Info)
  if self.DebugAIInfoTable then
    for _, InfoData in pairs(self.DebugAIInfoTable) do Info = Info .. InfoData end
  end
  return Info
end

function CharacterBase:AddDebugAIInfoTable(Key, StringInfo)
  if not self.DebugAIInfoTable then self.DebugAIInfoTable = {} end
  if Client then
    if Key and StringInfo then self.DebugAIInfoTable[Key] = StringInfo end
  else
    self.DebugAIInfoTable[Key] = string.format("%s=%s;", Key, StringInfo)
  end
end

function CharacterBase:InitIceDecalQueue(MaxNum)
  self.IceDecalQueue = {}
  self.MaxIceDecalQueue = 2 < MaxNum and math.floor(MaxNum) or 2
  self.IceDecalQueuePtr = 0
  for i = 1, self.MaxIceDecalQueue do table.insert(self.IceDecalQueue, false) end
end

function CharacterBase:EnqueueIceDecal(uIceDecalActor)
  if not slua.isValid(uIceDecalActor) then return end
  if self.IceDecalQueue == nil then self:InitIceDecalQueue(3) end
  local CurInsertIdx = self.IceDecalQueuePtr + 1
  if self.IceDecalQueue[CurInsertIdx] and slua.isValid(self.IceDecalQueue[CurInsertIdx]) then
    local uOldActor = self.IceDecalQueue[CurInsertIdx]
    if slua.isValid(uOldActor) then uOldActor:K2_DestroyActor() end
  end
  self.IceDecalQueue[CurInsertIdx] = uIceDecalActor
  self.IceDecalQueuePtr = (self.IceDecalQueuePtr + 1) % self.MaxIceDecalQueue
end

function CharacterBase:BP_ResetDataOnRespawn()
  EventSystem:postEvent(EVENTTYPE_INGAME_NORMAL, EVENTID_INGAME_ON_RESET_DATA_ON_RESPAWN, self.Object)
end

function CharacterBase:ToString() return string.format("%s(%s)", self.PlayerName, self.PlayerKey) end

function CharacterBase:LuaTriggerEntrySkillWithID(SkillID, bEnable)
  if not self.bClientCanTriggerSkill then return end
  if self.CharacterUltraHandRepFeature and not self.CharacterUltraHandRepFeature:CanUseUltraHand() then return end
  self:TriggerEntrySkillWithID(SkillID, bEnable)
end

function CharacterBase:SetClientCanTriggerSkill(bCanTriggerSkill) self.bClientCanTriggerSkill = bCanTriggerSkill end

function CharacterBase:SetClothMeshForceLod(bEnable)
  if not self.getAvatarComponent2 then return end
  local AvatarComp = self:getAvatarComponent2()
  if slua.isValid(AvatarComp) then
    AvatarComp:SetForceMeshLod(EAvatarSlotType.EAvatarSlotType_ClothesEquipemtSlot, bEnable)
  end
end

function CharacterBase:InitAddSpecialMoveInfo()
  if not CGame then return end
  local SpecialMoveConfig = GamePlayTools.GetCurrentConfig("SpecialMoveConfig")
  if not SpecialMoveConfig then return end
  for key, value in pairs(SpecialMoveConfig.SpecialMoveObjPathInfos) do
    if type(value) == "string" then
      local ObjMovementC = CGame:LoadOjectFromPath(value)
      if ObjMovementC then
        local ObjName = string.format("SpecialMoveObj_%d", key)
        local ObjMovement = CGame:NewObjectFromClass(self, ObjMovementC, ObjName)
        if ObjMovement and ObjMovement.SpecialMoveSetCharacterOwner then
          ObjMovement:SpecialMoveSetCharacterOwner(self)
          if slua.isValid(self.STCharacterMovement) then
            self.STCharacterMovement.SpecialObjes:Add(key, ObjMovement)
          end
        end
      end
    end
  end
  for key, value in pairs(SpecialMoveConfig.CustomMoveToSpecialMoveTypes) do
    if slua.isValid(self.STCharacterMovement) and type(value) == "number" then
      self.STCharacterMovement.CustomMoveModeToSpecialMoveType:Add(key, value)
    end
  end
  if SpecialMoveConfig.LuaCustomVariants then
    local ESpecialMovementTypeEnum = import("ESpecialMovementType")
    local LuaCustomMoveObj
    if slua.isValid(self.STCharacterMovement) then
      LuaCustomMoveObj = self.STCharacterMovement:GetSpecialMoveObjBySpecialMoveType(ESpecialMovementTypeEnum.SPECIAL_MOVE_LuaCustom)
    end
    if LuaCustomMoveObj and LuaCustomMoveObj.RegisterChildVariants then
      LuaCustomMoveObj:RegisterChildVariants(SpecialMoveConfig.LuaCustomVariants)
    end
  end
end

function CharacterBase:AddSpecialMoveInfo(SpecialMovementType, SpecialMovementObj)
  SpecialMovementObj:SpecialMoveSetCharacterOwner(self)
  if slua.isValid(self.STCharacterMovement) then
    self.STCharacterMovement.SpecialObjes:Add(SpecialMovementType, SpecialMovementObj)
  end
end

function CharacterBase:OnPlayerKeyRepExt()
  EventSystem:postEvent(EVENTTYPE_PLAYEREVENT_CHARACTER, EVENTID_PLAYEREVENT_PLAYERKEY_CHANGE, self.Object)
end

function CharacterBase:OnMovementActivated() end

function CharacterBase:HandleOnResolvePenetrationDelegate(bResolve, OldLoc, NewLoc)
  if bResolve then
    local Actor_C = import("/Script/Engine.Actor")
    local Character_C = import("/Script/Engine.Character")
    local ASTExtraVehicleBase_C = import("STExtraVehicleBase")
    local ASTExtraWeapon_C = import("STExtraWeapon")
    local FHitResult = import("/Script/Engine.HitResult")
    local uIgnoreActorArray = slua.Array(UEnums.EPropertyClass.Object, Actor_C)
    uIgnoreActorArray:Add(self.Object)
    local uWeapon = self:GetCurrentWeapon()
    if slua.isValid(uWeapon) then uIgnoreActorArray:Add(uWeapon) end
    local bIsPasswall = false
    local OutHits = slua.Array(UEnums.EPropertyClass.Struct, FHitResult)
    local HitResult = FHitResult()
    USTExtraBlueprintFunctionLibrary.TraceAllBlocks(OutHits, self.Object, OldLoc, NewLoc, HitResult, uIgnoreActorArray, false)
    local bHasVehicle = false
    if OutHits:Num() > 0 then
      for Index, Hit in pairs(OutHits) do
        local uHitActor = Hit.Actor
        if slua.isValid(uHitActor) then
          if not uHitActor:ActorHasTag("IgnorePassWall") and not uHitActor:ActorHasTag("PenetrationIgnorePassWall") and not Game:IsClassOf(uHitActor, Character_C) and not Game:IsClassOf(uHitActor, ASTExtraVehicleBase_C) and not Game:IsClassOf(uHitActor, ASTExtraWeapon_C) then
            bIsPasswall = true
          elseif Game:IsClassOf(uHitActor, ASTExtraVehicleBase_C) then
            bHasVehicle = true
          else
            uIgnoreActorArray:Add(uHitActor)
          end
        end
      end
    end
    if bHasVehicle then bIsPasswall = bIsPasswall or false end
    if bIsPasswall then
      local ResolveParams = import("/Script/ShadowTrackerExtra.ResolvePenetrationParams")()
      ResolveParams.AdjustRadius = 50
      ResolveParams.bLineTracePassWall = true
      ResolveParams.AdjustMaxHeight = 200
      for i = 0, uIgnoreActorArray:Num() - 1 do
        slua.IndexReference(ResolveParams, "PassWallIgnoreActors"):Add(uIgnoreActorArray:Get(i))
      end
      self:SetActorLocationSafetyWithParams(OldLoc, ResolveParams)
    end
  end
end

function CharacterBase:IsCastingSkillIDFix(InSkillID)
  if not self.GetSkillManager then return false end
  local uSkillManager = self:GetSkillManager()
  if not slua.isValid(uSkillManager) then return false end
  return uSkillManager:IsCastingSkillID(InSkillID)
end

function CharacterBase:RefreshThermalImagingLocal()
  local GameplayData = require("GameLua.GameCore.Data.GameplayData")
  local uPlayerCharacter = GameplayData.GetPlayerCharacter()
  if slua.isValid(uPlayerCharacter) then
    local ESightVisionMask = import("ESightVisionMask")
    local ESightVisionType = import("ESightVisionType")
    if uPlayerCharacter:HasAnySightVision(ESightVisionMask.ThermalImagingScope) then
      local UGameplayStatics = import("GameplayStatics")
      local uGameInstance = UGameplayStatics.GetGameInstance(uPlayerCharacter)
      if slua.isValid(uGameInstance) then
        uGameInstance:RefreshThermalImagingLocal(uPlayerCharacter)
      end
    end
  end
end

function CharacterBase:OnSplineMoveChanged(bEnter) self:HandleEnableMoveLayer(bEnter) end

function CharacterBase:HandleEnableMoveLayer(sEnable)
  local uAnimParamsComp = self:GetAnimParamsComponent()
  if not slua.isValid(uAnimParamsComp) then return end
  local bFPP = self:GetIsFPP()
  local uCharAnimInstance = self:GetCurrentMainLogicAnimInstance(bFPP)
  if slua.isValid(uCharAnimInstance) then
    if sEnable then
      local MoveInstanceClass = uAnimParamsComp:GetCustomizableAnimBP(uCharAnimInstance.FEATURE_MoveAnimInstanceID)
      if MoveInstanceClass then uAnimParamsComp:ActiveAnimContainerWithInstance("AC.Locomotion", MoveInstanceClass, false) end
    else
      uAnimParamsComp:ActiveAnimContainer("AC.Locomotion", true)
    end
  end
end

function CharacterBase:SpawnEmitterEffect(RelativeLocation, PSRef, AttachParent, RelativeScale)
  local KismetMathLibrary = import("KismetMathLibrary")
  local uPlayerController = self:GetPlayerControllerSafety()
  if slua.isValid(uPlayerController) then
    local ScreenAppearanceStatics = import("ScreenAppearanceStatics")
    local uScreenAppearanceActor = ScreenAppearanceStatics.GetScreenAppearanceManager(uPlayerController)
    if slua.isValid(uScreenAppearanceActor) then
      local uBloodSpotProvider, sProviderName
      if self.BloodSpot_Red == PSRef then sProviderName = "BloodSpot_Red"
      else sProviderName = "BloodSpot_Green" end
      uBloodSpotProvider = uScreenAppearanceActor:PlayDefaultScreenAppearance(uPlayerController, sProviderName, nil)
      if slua.isValid(uBloodSpotProvider) then
        local uTransform = KismetMathLibrary.MakeTransform(RelativeLocation, FRotator(0.0, 0.0, 90.0), RelativeScale)
        uBloodSpotProvider:UpdateRelativeTransform(uTransform)
        self.BloodScale = RelativeScale
        local EventDelegate = uBloodSpotProvider.AsyncLoadParticleComponentDone
        if slua.isValid(EventDelegate) and EventDelegate.Add then
          self._BloodSpotDelegateHandles = self._BloodSpotDelegateHandles or {}
          local OldInfo = self._BloodSpotDelegateHandles[sProviderName]
          if OldInfo and OldInfo.Handle then
            local OldProvider = OldInfo.Provider
            if slua.isValid(OldProvider) then
              local OldEventDelegate = OldProvider.AsyncLoadParticleComponentDone
              if slua.isValid(OldEventDelegate) and OldEventDelegate.Remove then
                OldEventDelegate:Remove(OldInfo.Handle)
              else
                slua.removeDelegate(OldInfo.Handle)
              end
            else
              slua.removeDelegate(OldInfo.Handle)
            end
            self._BloodSpotDelegateHandles[sProviderName] = nil
          end
          local DelegateHandle
          DelegateHandle = EventDelegate:Add(function(LoadedParticle)
            if DelegateHandle then
              if slua.isValid(EventDelegate) and EventDelegate.Remove then EventDelegate:Remove(DelegateHandle) end
              if self._BloodSpotDelegateHandles then
                local CurInfo = self._BloodSpotDelegateHandles[sProviderName]
                if CurInfo and CurInfo.Handle == DelegateHandle then self._BloodSpotDelegateHandles[sProviderName] = nil end
              end
              DelegateHandle = nil
            end
            if slua.isValid(LoadedParticle) and slua.isValid(self.Object) then
              self:ChangeParticleEffect(LoadedParticle, self.BloodScale)
            end
          end)
          self._BloodSpotDelegateHandles[sProviderName] = { Provider = uBloodSpotProvider, Handle = DelegateHandle }
        end
      end
    end
  end
end

function CharacterBase:ChangeAllAvatarMaterialToFeatureMaterial(material)
  local uAvatarComp2 = self:getAvatarComponent2()
  if slua.isValid(uAvatarComp2) then uAvatarComp2:ChangeAllMeshToFeatureMaterial(material) end
  local WeaponManager = self:GetWeaponManager()
  if slua.isValid(WeaponManager) then WeaponManager:ChangeAllMeshToFeatureMaterial(material) end
end

function CharacterBase:ClearAllAvatarFeatureMaterial()
  if self.getAvatarComponent2 then
    local uAvatarComp2 = self:getAvatarComponent2()
    if slua.isValid(uAvatarComp2) then uAvatarComp2:ClearAllFeatureMaterial() end
  end
  if self.GetWeaponManager then
    local WeaponManager = self:GetWeaponManager()
    if slua.isValid(WeaponManager) then WeaponManager:ClearAllFeatureMaterial() end
  end
end

function CharacterBase:CheckParachuteLandShouldUseSkill()
  local UKismetSystemLibrary = import("KismetSystemLibrary")
  local uPawnFor = self:GetActorForwardVector()
  local uPawnLoc = self:K2_GetActorLocation()
  local uForVec2D = uPawnFor:GetSafeNormal2D(1.0E-6)
  local EndPath = uPawnLoc + uForVec2D * 200
  local uHitResult = import("/Script/Engine.HitResult")()
  local EDrawDebugTrace = import("EDrawDebugTrace")
  local ActorClass = import("/Script/Engine.Actor")
  local ActorsToIgnore = slua.Array(UEnums.EPropertyClass.Object, ActorClass)
  local bHit = UKismetSystemLibrary.LineTraceSingle(self.Object, uPawnLoc, EndPath, 6, true, ActorsToIgnore, EDrawDebugTrace.None, uHitResult, true, FLinearColor.Red, FLinearColor.Green, 1)
  if bHit then return false end
  return true
end

function CharacterBase:IsOverlappingWithArea(TargetActor)
  local Result = false
  local AreaActor
  local DSReviveSubsystem = SubsystemMgr:Get("DSReviveSubsystem")
  local POIGeneralAreaClass = slua.loadClass("/Game/Mod/EvoBase/BluePrints/Actor/BaseLevelEnterArea.BaseLevelEnterArea")
  local uAreaList = self:GetOverlappingActors(slua.Array(UEnums.EPropertyClass.Object, import("/Script/Engine.Actor")), POIGeneralAreaClass)
  for _, uArea in pairs(uAreaList) do
    if slua.isValid(uArea) and (TargetActor == nil or TargetActor == uArea) and DSReviveSubsystem.POIAreaRegisteredInfo[uArea] and uArea.CheckPlayerCanSelfRevive then
      if uArea:CheckPlayerCanSelfRevive(self.Object) then Result = true AreaActor = uArea break end
    end
  end
  return Result, AreaActor
end

function CharacterBase:IsOverlappingIgnoringArea(TargetActor)
  local Result = false
  local AreaActor
  local DSReviveSubsystem = SubsystemMgr:Get("DSReviveSubsystem")
  local POIGeneralAreaClass = slua.loadClass("/Game/Mod/EvoBase/BluePrints/Actor/BaseLevelEnterArea.BaseLevelEnterArea")
  local uAreaList = self:GetOverlappingActors(slua.Array(UEnums.EPropertyClass.Object, import("/Script/Engine.Actor")), POIGeneralAreaClass)
  for _, uArea in pairs(uAreaList) do
    if slua.isValid(uArea) and TargetActor ~= uArea and DSReviveSubsystem.POIAreaRegisteredInfo[uArea] and uArea.CheckPlayerCanSelfRevive then
      if uArea:CheckPlayerCanSelfRevive(self.Object) then Result = true AreaActor = uArea break end
    end
  end
  return Result, AreaActor
end

function CharacterBase:UpdatePOIReviveAreaID(uExcludeArea)
  local uAreaList = self:GetOverlappingActors(slua.Array(UEnums.EPropertyClass.Object, import("/Script/Engine.Actor")), import("/Script/Engine.Actor"))
  for _, uArea in pairs(uAreaList) do
    if slua.isValid(uArea) and uArea ~= uExcludeArea and uArea.HandleSetReviveState ~= nil and uArea:HandleSetReviveState(uArea, true) then return true end
  end
  return false
end

function CharacterBase:OnServerSpectatorKickFromGame()
  local CarryBackComp = self:GetCarryBackComp()
  local hasBeCarryBack = self:HasState(EPawnState.BeCarriedBack)
  local hasCarryBack = self:HasState(EPawnState.Carryback)
  if slua.isValid(CarryBackComp) then
    if hasBeCarryBack then
      local CarryBackCharOfKickPlayer = CarryBackComp.CarryBackCharacter
      if slua.isValid(CarryBackCharOfKickPlayer) then
        local CarryBackCharOfKickPlayerComp = CarryBackCharOfKickPlayer:GetCarryBackComp()
        if slua.isValid(CarryBackCharOfKickPlayerComp) then CarryBackCharOfKickPlayerComp:RPC_ServerManualBreakCarryBackState() end
      end
    end
    if hasCarryBack then CarryBackComp:RPC_ServerManualBreakCarryBackState() end
  end
end

function CharacterBase:GetPhysicsType()
  local nPhysicsType = 0
  local USTExtraGameInstance = import("STExtraGameInstance")
  local uGameInstance = USTExtraGameInstance.GetInstance()
  if slua.isValid(uGameInstance) then
    local ModType = uGameInstance.ModType
    local ModType2 = uGameInstance.ModType2
    if ModType == "Escape" or ModType2 == "Escape" then
      if self.HeroPropFeature and self.HeroPropFeature:GetCurrentHeroID() ~= nil then nPhysicsType = 2 end
    elseif (ModType == "Halloween4" or ModType2 == "Halloween4") and self.HeroPropFeature then
      if self.HeroPropFeature:GetCurrentHeroID() ~= nil then nPhysicsType = 1 end
    end
  end
  return nPhysicsType
end

function CharacterBase:ActivateCharacterMovement()
  if not slua.isValid(self.CharacterMovement) then return end
  local ENetRole = import("ENetRole")
  self:SetReplicateMovement(true)
  if Client then self.bReplicateMovement = true end
  self.CharacterMovement:SetMovementMode(EMovementMode.MOVE_Walking, 0)
  self.CharacterMovement:Activate(false)
  self.CharacterMovement:SetComponentTickEnabled(true)
  if self.Role == ENetRole.ROLE_SimulatedProxy then
    local UGameplayStatics = import("GameplayStatics")
    self.CharacterMovement:SetClientReceiveServerStateTimestamp(UGameplayStatics.GetTimeSeconds(CGameWorld))
  elseif self.Role == ENetRole.ROLE_Authority then
    self.CharacterMovement:ForceNetUpdate()
  end
  self.CharacterMovement.bForbidActiveWhenAttachParent = true
end

function CharacterBase:DeactivateCharacterMovement(bForce)
  if not slua.isValid(self.CharacterMovement) then return end
  if bForce then self.CharacterMovement.bForbidActiveWhenAttachParent = false end
  self:SetReplicateMovement(false)
  if not Client then self.CharacterMovement:SetMovementMode(EMovementMode.MOVE_None, 0) end
  self.CharacterMovement:Deactivate()
  self.CharacterMovement:SetComponentTickEnabled(false)
  if Client then
    local uController = slua_GameFrontendHUD:GetPlayerController()
    if slua.isValid(uController) and uController:IsSpectator() then
      self.CharacterMovement:ResetSimulateMoveCaches(false)
    end
  end
end

function CharacterBase:MultiCast_GenericRPC(ID, Bytes)
  local GenericRPCEnums = require("GameLua.Mod.BaseMod.GamePlay.GenericRPC.GenericRPCEnums")
  local GenericRPCUtil = require("GameLua.Mod.BaseMod.GamePlay.GenericRPC.GenericRPCUtil")
  GenericRPCUtil._OnRecv(self, ID, GenericRPCEnums.EGenericRPCDirection.Multicast, Bytes)
end

-- ========================================================================
-- 1.5 PREMIUM STYLE HELPERS (ported from 1.lua — ShayanPremiumUI)
-- Rainbow borders, glassmorphism, floating particles, neon glows
-- ========================================================================

local ShayanPremiumStyle = (function()
    local Style = {}
    local COLORS = {
        NEON_PINK   = {1.0, 0.1, 0.6},
        NEON_CYAN   = {0.0, 0.9, 1.0},
        NEON_PURPLE = {0.6, 0.2, 1.0},
        NEON_GREEN  = {0.1, 1.0, 0.4},
        NEON_ORANGE = {1.0, 0.5, 0.0},
        NEON_YELLOW = {1.0, 0.9, 0.0},
    }
    -- Subtle emerald-to-champagne shimmer; no full-spectrum flashing.
    function Style.rainbow(offset, alpha)
        local wave = 0.5 + 0.5 * math.sin(offset * 0.32)
        return 0.12 + wave * 0.70, 0.74 + wave * 0.06, 0.62 - wave * 0.22, alpha or 1.0
    end
    function Style.glow(d, x, y, size, intensity, r, g, b)
        for i = 2, 1, -1 do
            local glowSize  = size + (i * 4)
            local glowAlpha = intensity * (0.2 * i)
            d.circle(x, y, glowSize, r, g, b, glowAlpha * 0.3, true)
        end
    end
    function Style.animatedBorder(d, x, y, w, h, thickness, time)
        local segments = 8
        local segW = w / segments
        for i = 0, segments - 1 do
            local r, g, b = Style.rainbow(time * 2 + i * 0.3)
            local alpha = 0.6 + 0.4 * math.sin(time * 3 + i * 0.5)
            d.rect(x + i * segW, y,                     segW, thickness, r, g, b, alpha, true)
            d.rect(x + i * segW, y + h - thickness,     segW, thickness, r, g, b, alpha, true)
        end
        local segmentsH = math.max(1, math.floor(h / (w / segments)))
        for i = 0, segmentsH - 1 do
            local r, g, b = Style.rainbow(time * 2 + i * 0.3 + 1)
            local alpha = 0.6 + 0.4 * math.sin(time * 3 + i * 0.5 + 1)
            d.rect(x,                 y + i * (w / segments), thickness, w / segments, r, g, b, alpha, true)
            d.rect(x + w - thickness, y + i * (w / segments), thickness, w / segments, r, g, b, alpha, true)
        end
    end
    function Style.initParticles(count)
        local list = {}
        for i = 1, count do
            list[#list + 1] = {
                x     = math.random(),
                y     = math.random(),
                size  = math.random(2, 6),
                speed = math.random(10, 30) / 100,
                color = math.random(1, 6),
                alpha = math.random(30, 80) / 100,
            }
        end
        return list
    end
    function Style.drawParticles(d, w, h, time, particles)
        local set = { COLORS.NEON_PINK, COLORS.NEON_CYAN, COLORS.NEON_PURPLE,
                      COLORS.NEON_GREEN, COLORS.NEON_ORANGE, COLORS.NEON_YELLOW }
        for _, p in ipairs(particles) do
            local px = (p.x * w + math.sin(time * p.speed * 2) * 20) % w
            local py = (p.y * h + time * p.speed * 50) % h
            local c  = set[p.color]
            local pulse = 0.5 + 0.5 * math.sin(time * 2 + p.x * 10)
            d.circle(px, py, p.size * pulse, c[1], c[2], c[3], p.alpha * pulse * 0.5, true)
        end
    end
    function Style.drawGrid(d, w, h, time)
        local gridSize = 100
        local offset   = (time * 20) % gridSize
        for i = 0, w, gridSize do
            local a = 0.03 + 0.02 * math.sin(time + i * 0.01)
            d.line(i + offset, 0, i + offset, h, 0.2, 0.5, 0.8, a, 1)
        end
        for i = 0, h, gridSize do
            local a = 0.03 + 0.02 * math.sin(time + i * 0.01)
            d.line(0, i + offset, w, i + offset, 0.2, 0.5, 0.8, a, 1)
        end
    end
    Style.COLORS = COLORS
    return Style
end)()

-- ========================================================================
-- 2. ESP DISPLAY AND MENU (ESP V2 ONLY)
-- ========================================================================

local ShayanHUD = (function()
local HUD = {}
HUD.__index = HUD
local floor, sqrt, sin, cos = math.floor, math.sqrt, math.sin, math.cos
local min, max, abs = math.min, math.max, math.abs
local huge = math.huge
local pi = math.pi
local ARC = {}
for i = 0, 8 do
    local angle = (-165 + 150 * i / 8) * pi / 180
    ARC[i + 1] = { cos(angle), sin(angle) }
end
local PALETTE = {
    {'Red',1,0.10,0.14},{'Cyan',0,0.9,1},{'Green',0.10,0.9,0.25},
    {'Yellow',1,0.9,0.05},{'Orange',1,0.45,0.05},{'Purple',0.62,0.25,1},
    {'Pink',1,0.25,0.65},{'White',1,1,1},{'Blue',0.1,0.35,1},{'Lime',0.60,1,0.05}
}
local PAGES = { {'page_v2','ESP V2'}, {'page_aim','Aim Menu'}, {'page_visual','Visual'} }
local AIMS = { 'Forced Auto Aim', 'Aim Assist', 'Sniper Aim', 'Mortar Aim', 'Ignore Knocked Players', 'Ignore Bots', 'Visibility Check' }
local AIM_KEYS = { 'force', 'assistant', 'sniper', 'mortar', 'ignoreKnocked', 'ignoreBots', 'visibility' }
local AIM_SUPPORTED = { force = true, assistant = true, sniper = true, mortar = true, ignoreKnocked = true, ignoreBots = true, visibility = true, circle = true, smallCrosshair = true, bypass = true }
local AIM_STATUS = {
    force_disabled='Force Aimbot OFF',
    idle_ADS='Waiting for ADS', weapon_unavailable='Weapon unavailable',
    weapon_identity_unavailable='Weapon type unavailable', mortar_not_placed='Place mortar first',
    mortar_disabled='Mortar OFF', assistant_disabled='Assistant OFF', sniper_disabled='Sniper OFF',
    no_target_in_circle='No target inside circle', context_unavailable='Waiting for game data',
    context_changed='Waiting for current player', rotation_call_accepted='Aim command sent',
    priming_delta='Aim ready', target_left_circle='Target left circle'
}
local function finite(v) return type(v) == 'number' and v == v and v ~= huge and v ~= -huge end
local function clamp(v, lo, hi) return max(lo, min(hi, v)) end
local function number(v, fallback, lo, hi) return finite(v) and clamp(v, lo, hi) or fallback end
local function validId(id) return (type(id) == 'string' and #id > 0) or finite(id) end
local function inside(x, y, bx, by, bw, bh) return x >= bx and y >= by and x <= bx + bw and y <= by + bh end
local function shortName(value, bot)
    if type(value) ~= 'string' or #value == 0 then return bot and 'BOT' or 'ENEMY' end
    local s = value:sub(1, 52):gsub('[%z\1-\31\127]', '')
    local i, last = 1, 0
    while i <= #s and i <= 48 do
        local b = s:byte(i)
        local size = b < 128 and 1 or (b < 224 and 2 or (b < 240 and 3 or 4))
        if i + size - 1 > min(#s, 48) then break end
        last = i + size - 1
        i = last + 1
    end
    return s:sub(1, last)
end
local function previousChar(s)
    local i = #s
    while i > 1 and s:byte(i) >= 128 and s:byte(i) < 192 do i = i - 1 end
    return s:sub(1, i - 1)
end
local function fitName(renderer, value, size, maximum)
    local text = value
    while #text > 0 do
        local measured = renderer.measureText and renderer.measureText(text, size)
        local width = finite(measured) and measured >= 0 and measured or #text * size
        if width <= maximum then return text, width end
        text = previousChar(text)
    end
    return '', 0
end
local function boxed(d, x, y, w, h, value, size, r, g, b, a, align)
    if w <= 0 or h <= 0 then return end
    if d.textBox then return d.textBox(x, y, w, h, value, size, r, g, b, a, align or 'center') end
    local font = min(size, h * 0.72)
    local text, tw = fitName(d, value, font, w)
    local tx = x
    if align == 'right' then tx = x + w - tw
    elseif align ~= 'left' then tx = x + (w - tw) * 0.5 end
    if #text > 0 then d.text(tx, y + (h - font) * 0.5, text, font, r, g, b, a) end
end
local function bevel(d, x, y, w, h, cut, r, g, b, a, strokeR, strokeG, strokeB)
    cut = min(cut, w * 0.2, h * 0.4)
    d.rect(x, y + cut, w, h - 2 * cut, r, g, b, a, true, 1)
    for i = 0, 1 do
        local band = cut * 0.5
        d.rect(x, y + i * band, w - cut + (i + 0.5) * band, band, r, g, b, a, true, 1)
        d.rect(x + (i + 0.5) * band, y + h - cut + i * band, w - (i + 0.5) * band, band, r, g, b, a, true, 1)
    end
    if strokeR then
        local t = max(0.8, h / 24)
        d.line(x, y, x + w - cut, y, strokeR, strokeG, strokeB, 1, t)
        d.line(x + w - cut, y, x + w, y + cut, strokeR, strokeG, strokeB, 1, t)
        d.line(x + w, y + cut, x + w, y + h, strokeR, strokeG, strokeB, 1, t)
        d.line(x + w, y + h, x + cut, y + h, strokeR, strokeG, strokeB, 1, t)
        d.line(x + cut, y + h, x, y + h - cut, strokeR, strokeG, strokeB, 1, t)
        d.line(x, y + h - cut, x, y, strokeR, strokeG, strokeB, 1, t)
    end
end
local ROWS = {
    {'enabled', 'Enable ESP'}, 
    {'enemyCount', 'Show Enemy Count'},
    {'botCount', 'Show Bot Count'},
    {'health', 'Show Enemy Health Bar'}, 
    {'names', 'Show Enemy Names'}, 
    {'distance', 'Show Distance to Player'},
    {'enemyHeadLines', 'Draw Lines to Enemy Head'}, 
    {'enemyFeetLines', 'Enemy Feet Lines'},
    {'botHeadLines', 'Bot Head Lines'}, 
    {'botFeetLines', 'Bot Feet Lines'},
    {'compass', 'Compass'}
}
local KEYS = {}
for i = 1, #ROWS do
    KEYS[ROWS[i][1]] = true
    ROWS[i][3] = ROWS[i][1]:sub(1, 5) == 'enemy'
end

function HUD.new(renderer, config)
    assert(type(renderer) == 'table', 'renderer table is required')
    for _, key in ipairs({'line', 'rect', 'circle', 'text'}) do
        assert(type(renderer[key]) == 'function', 'renderer.' .. key .. ' is required')
    end
    assert(renderer.measureText == nil or type(renderer.measureText) == 'function',
        'renderer.measureText must be a function when supplied')
    config = type(config) == 'table' and config or {}
    local self = setmetatable({
        renderer = renderer, records = {}, seen = {}, features = {}, featureSets = {}, controls = {},
        count = 0, enemies = 0, bots = 0, overflow = 0, invalid = 0,
        sourceOverflow = 0, totalOverflow = 0, overflowExact = true,
        enemyLabel = 'ENEMIES 0', botLabel = 'BOTS 0', enemyNumber = '0', botNumber = '0', limitLabel = '',
        range = number(config.range, 300, 1, 10000),
        maxActors = floor(number(config.maxActors, 256, 1, 2048)),
        staleAfter = number(config.staleAfter, 0.6, 0.05, 10),
        labelInterval = number(config.labelInterval, 0.2, 0.02, 1),
        buttonX = number(config.buttonX, 18, 0, 100000),
        buttonY = number(config.buttonY, 92, 0, 100000),
        rowHeight = 29, headerHeight = 82, closeWidth = 42, navWidth = 152,
        menuTitle = 'SHAYAN', menuVersion = '@SHAYAN_OWNER',
style = 'v2', page = 'v2',
visual = { ipadView = false, wallHack = false, visibleColor = 1, occludedColor = 2 },
featureStatus = {}, aimStatus = {}, weaponStatus = {}, bypassStatus = {},
aim = { force = false, assistant = false, sniper = false, mortar = false, ignoreKnocked = true, ignoreBots = true, visibility = true, circle = false, smallCrosshair = false, bypass = false },
width = 1280, height = 720, open = false, capture = nil,
snapshotAt = nil, lastTime = nil, stale = true,
px = 0, py = 0, pz = 0, yaw = 0, playerAiming = false
}, HUD)
do
    local values = {}
    local supplied = type(config.featureSets) == 'table' and config.featureSets['v2'] or config.features
    for i = 1, #ROWS do
        local key = ROWS[i][1]
        values[key] = not (type(supplied) == 'table' and supplied[key] == false)
    end
    self.featureSets['v2'] = values
end
    self.features = self.featureSets['v2']
    if type(config.visual) == 'table' then
        self.visual.ipadView = config.visual.ipadView == true
        self.visual.wallHack = config.visual.wallHack == true
        self.visual.visibleColor = floor(number(config.visual.visibleColor, 1, 1, 10))
        self.visual.occludedColor = floor(number(config.visual.occludedColor, 2, 1, 10))
    end
    if type(config.aim) == 'table' then
        for key in pairs(AIM_SUPPORTED) do self.aim[key] = config.aim[key] == true end
    end
    self.aim.bypass = true
    self:resize(self.width, self.height)
    return self
end

function HUD:_clearActors(stale)
    for i = 1, self.count do
        local row = self.records[i]
        row.id, row.name, row.rawName, row.distanceLabel = nil, nil, nil, nil
    end
    for key in pairs(self.seen) do self.seen[key] = nil end
    self.count, self.enemies, self.bots, self.overflow, self.invalid = 0, 0, 0, 0, 0
    self.sourceOverflow, self.totalOverflow = 0, 0
    self.overflowExact = true
    self.enemyLabel, self.botLabel, self.limitLabel = 'ENEMIES 0', 'BOTS 0', ''
    self.enemyNumber, self.botNumber = '0', '0'
    self.snapshotAt, self.stale = nil, stale ~= false
end

function HUD:reset()
    self:_clearActors(true)
    self.lastTime, self.capture = nil, nil
end

function HUD:update(actors, player, now)
    if not finite(now) or type(actors) ~= 'table' or type(player) ~= 'table'
        or not finite(player.x) or not finite(player.y) or not finite(player.z)
        or not finite(player.yaw) then
        self:_clearActors(true)
        return false
    end
    if self.lastTime and now < self.lastTime then
        self:_clearActors(true)
        self.lastTime = now
        return false
    end
    self.lastTime = now
    self.px, self.py, self.pz, self.yaw = player.x, player.y, player.z, player.yaw
    self.playerAiming = player.aiming == true or player.aiming == 1
    for key in pairs(self.seen) do self.seen[key] = nil end
    local oldCount, count, enemies, bots, invalid = self.count, 0, 0, 0, 0
    local total, range2 = #actors, self.range * self.range
    for i = 1, min(total, self.maxActors) do
        local actor = actors[i]
        local valid = type(actor) == 'table' and validId(actor.id)
            and type(actor.isBot) == 'boolean'
            and finite(actor.x) and finite(actor.y) and finite(actor.z)
            and finite(actor.health) and finite(actor.maxHealth) and actor.maxHealth > 0
        if not valid then
            invalid = invalid + 1
        elseif not self.seen[actor.id] and actor.id ~= player.id
            and not (player.team ~= nil and actor.team == player.team)
            and actor.alive ~= false and (actor.health > 0 or actor.knocked == true) then
            self.seen[actor.id] = true
            local dx, dy, dz = actor.x - player.x, actor.y - player.y, actor.z - player.z
            local dist2 = dx * dx + dy * dy + dz * dz
            if finite(dist2) and dist2 <= range2 then
                count = count + 1
                local row = self.records[count]
                if not row then row = {} self.records[count] = row end
                local changed = row.id ~= actor.id
                if changed or row.rawName ~= actor.name or row.bot ~= actor.isBot then
                    row.name = shortName(actor.name, actor.isBot)
                    row.rawName = type(actor.name) == 'string' and actor.name or nil
                end
                row.id, row.bot = actor.id, actor.isBot
                row.dx, row.dy = dx, dy
                row.health = clamp(actor.health / actor.maxHealth, 0, 1)
                local hp = floor(row.health * 100 + 0.5)
                if row.healthPercent ~= hp or not row.healthLabel then
                    row.healthPercent, row.healthLabel = hp, tostring(hp) .. '%'
                end
                row.headX = finite(actor.headX) and actor.headX or nil
                row.headY = finite(actor.headY) and actor.headY or nil
                row.feetX = finite(actor.feetX) and actor.feetX or nil
                row.feetY = finite(actor.feetY) and actor.feetY or nil
                if changed or not row.nextLabel or now >= row.nextLabel then
                    local distance = floor(sqrt(dist2) + 0.5)
                    if changed or row.distance ~= distance or not row.distanceLabel then
                        row.distance, row.distanceLabel = distance, tostring(distance) .. ' m'
                    end
                    row.nextLabel = now + self.labelInterval
                end
                if row.bot then bots = bots + 1 else enemies = enemies + 1 end
            end
        end
    end
    for i = count + 1, oldCount do
        local row = self.records[i]
        row.id, row.name, row.rawName, row.distanceLabel = nil, nil, nil, nil
    end
    local overflow = max(0, total - self.maxActors)
    if self.enemies ~= enemies then self.enemyLabel = 'ENEMIES ' .. enemies self.enemyNumber = tostring(enemies) end
    if self.bots ~= bots then self.botLabel = 'BOTS ' .. bots self.botNumber = tostring(bots) end
    self.count, self.enemies, self.bots = count, enemies, bots
    self.overflow, self.invalid = overflow, invalid
    self:_refreshLimit()
    self.snapshotAt, self.stale = now, false
    return true
end

function HUD:resize(width, height)
    if not finite(width) or not finite(height) or width <= 0 or height <= 0 then return false end
    if self.width == width and self.height == height and self._resized then return true end
    self.width, self.height = width, height
    self.uiScale = min(1.5, width / 1280, height / 720)
    local bs = min(self.uiScale, width / 132, height / 38)
    self.buttonW, self.buttonH = 146 * bs, 42 * bs
    self.buttonX = clamp(self.buttonX, 0, width - self.buttonW)
    self.buttonY = clamp(self.buttonY, 0, height - self.buttonH)
    local panelHeight = 540
    local s = min(self.uiScale, width / 720, height / panelHeight)
    self.panelScale, self.panelW, self.panelH = s, 720 * s, panelHeight * s
    self:_layoutPanel()
    self._resized = true
    return true
end

function HUD:_layoutPanel()
    local s = self.panelScale
    local gap = 14 * s
    local margin = 10 * s
    local maxX = max(margin, self.width - self.panelW - margin)
    local maxY = max(margin, self.height - self.panelH - margin)

    -- Prefer the side of the launcher with enough room. Never place the panel
    -- underneath the launcher unless the viewport physically cannot fit it.
    local right = self.buttonX + self.buttonW + gap
    local left = self.buttonX - self.panelW - gap
    if right <= self.width - margin and right + self.panelW <= self.width - margin then
        self.panelX = clamp(right, margin, maxX)
        self.panelY = clamp(self.buttonY - 34 * s, margin, maxY)
    elseif left >= margin then
        self.panelX = clamp(left, margin, maxX)
        self.panelY = clamp(self.buttonY - 34 * s, margin, maxY)
    else
        -- No side fit: put it below the launcher, with a guaranteed gap.
        self.panelX = clamp(self.buttonX, margin, maxX)
        local below = self.buttonY + self.buttonH + gap
        self.panelY = below + self.panelH <= self.height - margin
            and below or clamp(self.buttonY - self.panelH - gap, margin, maxY)
    end
end

function HUD:setFeature(key, value)
    if not KEYS[key] or type(value) ~= 'boolean' then return false end
    self.features[key] = value
    return true
end

function HUD:exportSettings()
    local copy = { buttonX = self.buttonX, buttonY = self.buttonY, style = self.style, features = {}, featureSets = {}, visual = {}, aim = {} }
    copy.featureSets['v2'] = {}
    for key in pairs(KEYS) do copy.featureSets['v2'][key] = self.featureSets['v2'][key] end
    for key in pairs(KEYS) do copy.features[key] = self.features[key] end
    for key, value in pairs(self.visual) do copy.visual[key] = value end
    for key, value in pairs(self.aim) do copy.aim[key] = value end
    return copy
end

function HUD:setFeatureStatus(status) self.featureStatus = type(status) == 'table' and status or {} end
function HUD:setAimStatus(status) self.aimStatus = type(status) == 'table' and status or {} end
function HUD:setWeaponStatus(status) self.weaponStatus = type(status) == 'table' and status or {} end
function HUD:setBypassStatus(status) self.bypassStatus = type(status) == 'table' and status or {} end

function HUD:getControls()
    local list, n = self.controls, 0
    local function add(id, action, x, y, w, h, z, drag, enabled)
        n = n + 1
        local c = list[n] or {}
        list[n] = c
        c.id, c.action, c.x, c.y, c.w, c.h = id, action, x, y, w, h
        c.z, c.drag, c.enabled = z, drag == true, enabled ~= false
    end

    add('menu', 'button', self.buttonX, self.buttonY, self.buttonW, self.buttonH, 0, true)

    if self.open then
        local s, x, y = self.panelScale, self.panelX, self.panelY
        local navW = self.navWidth * s
        add('panel', 'panel', x, y, self.panelW, self.panelH, 1, true)

        add('dragbar', 'dragbar', x + 270 * s, y + 8 * s,
            max(70 * s, self.panelW - 430 * s), 24 * s, 5, true)

        add('close', 'close', x + self.panelW - 58 * s, y + 40 * s, 42 * s, 30 * s, 8)

        for i = 1, #PAGES do
            add('page' .. i, PAGES[i][1],
                x + 11 * s,
                y + (96 + (i - 1) * 66) * s,
                (navW - 22 * s), 50 * s, 6)
        end

        local content = x + navW
        local cw = self.panelW - navW

        if self.page == 'v2' then
            for i = 1, #ROWS do
                add('feature' .. i, 'feature_' .. ROWS[i][1],
                    content + 16 * s,
                    y + (157 + (i - 1) * self.rowHeight) * s,
                    cw - 32 * s, self.rowHeight * s, 6)
            end
        elseif self.page == 'aim' then
            for i = 1, #AIM_KEYS do
                local key = AIM_KEYS[i]
                add('aim' .. i, 'aim_' .. key,
                    content + 16 * s,
                    y + (160 + (i - 1) * 32) * s,
                    cw - 32 * s, 28 * s, 6, false, AIM_SUPPORTED[key] == true)
            end
            add('aimcircle', 'aim_circle', content + 16 * s, y + 390 * s, cw - 32 * s, 28 * s, 6)
            add('smallcrosshair', 'aim_smallCrosshair', content + 16 * s, y + 422 * s, cw - 32 * s, 28 * s, 6)
            add('bypass', 'aim_bypass', content + 16 * s, y + 454 * s, cw - 32 * s, 28 * s, 6)
        elseif self.page == 'visual' then
            add('ipad', 'ipadView', content + 16 * s, y + 160 * s, cw - 32 * s, 30 * s, 6)
            add('wall', 'wallHack', content + 16 * s, y + 194 * s, cw - 32 * s, 30 * s, 6)
            for category = 1, 2 do
                for i = 1, 10 do
                    local prefix = category == 1 and 'visible_' or 'occluded_'
                    add(prefix .. i, prefix .. i,
                        content + (20 + (i - 1) * 31) * s,
                        y + (261 + (category - 1) * 82) * s,
                        25 * s, 25 * s, 6)
                end
            end
        end
    end

    for i = n + 1, #list do list[i] = nil end
    return list
end

function HUD:activateControl(action)
    if action == 'button' then self.open = not self.open return true end
    if action == 'close' then self.open = false return true end
    if action == 'panel' or action == 'dragbar' then return true end
    if type(action) ~= 'string' then return false end
    local page = action:match('^page_(%w+)$')
    if page == 'v2' then
        self.page, self.style = 'v2', 'v2'
        self.features = self.featureSets['v2']
        return true
    elseif page == 'aim' or page == 'visual' then
        self.page = page
        return true
    end
    local key = action:match('^feature_(.+)$')
    if key and KEYS[key] then return self:setFeature(key, not self.features[key]) end
    local aimKey = action:match('^aim_(.+)$')
    if aimKey then
        if not AIM_SUPPORTED[aimKey] then return false end
        if aimKey == 'bypass' then self.aim.bypass = true return true end
        self.aim[aimKey] = not self.aim[aimKey]
        return true
    end
    if action == 'ipadView' or action == 'wallHack' then
        self.visual[action] = not self.visual[action]
        return true
    end
    local category, index = action:match('^(%a+)_(%d+)$')
    index = tonumber(index)
    if index and index >= 1 and index <= 10 then
        if category == 'visible' then self.visual.visibleColor = index return true end
        if category == 'occluded' then self.visual.occludedColor = index return true end
    end
    local step = max(12, 24 * self.uiScale)
    if action == 'move_left' then self.buttonX = self.buttonX - step
    elseif action == 'move_right' then self.buttonX = self.buttonX + step
    elseif action == 'move_up' then self.buttonY = self.buttonY - step
    elseif action == 'move_down' then self.buttonY = self.buttonY + step
    elseif action == 'reset_position' then self.buttonX, self.buttonY = 18 * self.uiScale, 92 * self.uiScale
    else return false end
    self.buttonX = clamp(self.buttonX, 0, self.width - self.buttonW)
    self.buttonY = clamp(self.buttonY, 0, self.height - self.buttonH)
    self:_layoutPanel()
    return true
end

function HUD:_refreshLimit()
    local total = self.overflow + self.sourceOverflow
    if total ~= self.totalOverflow or self._labelExact ~= self.overflowExact then
        self.totalOverflow = total
        self._labelExact = self.overflowExact
        self.limitLabel = not self.overflowExact and 'LIMIT: MORE'
            or (total > 0 and ('LIMIT +' .. total) or '')
    end
end

function HUD:setSourceOverflow(value, exact)
    if not finite(value) or value < 0 or value ~= floor(value) then return false end
    if exact ~= nil and type(exact) ~= 'boolean' then return false end
    self.sourceOverflow = min(value, 1000000)
    self.overflowExact = exact ~= false and value <= 1000000
    self:_refreshLimit()
    return true
end

function HUD:getStats()
    return {
        enemies = self.enemies, bots = self.bots, tracked = self.count,
        overflow = self.totalOverflow, sourceOverflow = self.sourceOverflow,
        overflowExact = self.overflowExact, invalid = self.invalid, stale = self.stale
    }
end

function HUD:_hit(x, y)
    local best
    for _, c in ipairs(self:getControls()) do
        if inside(x, y, c.x, c.y, c.w, c.h) and (not best or c.z >= best.z) then best = c end
    end
    return best and (best.enabled and best.action or 'panel') or nil
end

function HUD:pointer(kind, x, y, id)
    if id == nil then id = 0 end
    local cap = self.capture
    if kind == 'cancel' then
        if cap and cap.id == id then self.capture = nil return true end
        return false
    end
    if not finite(x) or not finite(y) then
        if kind == 'up' and cap and cap.id == id then self.capture = nil return true end
        return false
    end
    if kind == 'down' then
        if cap then return false end
        local target = self:_hit(x, y)
        if not target then return false end
        local baseX, baseY = self.buttonX, self.buttonY
        if self.open and target ~= 'button' then baseX, baseY = self.panelX, self.panelY end
        self.capture = { id = id, target = target, x = x, y = y, bx = baseX, by = baseY, dragged = false }
        return true
    end
    if not cap or cap.id ~= id then return false end
    if kind ~= 'move' and kind ~= 'up' then return false end
    local dx, dy = x - cap.x, y - cap.y
    if dx * dx + dy * dy > 36 then cap.dragged = true end

    if cap.dragged then
        if cap.target == 'button' and not self.open then
            self.buttonX = clamp(cap.bx + dx, 0, self.width - self.buttonW)
            self.buttonY = clamp(cap.by + dy, 0, self.height - self.buttonH)
        elseif self.open then
            self.panelX = clamp(cap.bx + dx, 0, self.width - self.panelW)
            self.panelY = clamp(cap.by + dy, 0, self.height - self.panelH)
            self.buttonX = clamp(self.panelX - self.buttonW - 10 * self.panelScale, 0, self.width - self.buttonW)
            self.buttonY = clamp(self.panelY + 12 * self.panelScale, 0, self.height - self.buttonH)
        end
    end
    if kind == 'up' then
        if not cap.dragged and self:_hit(x, y) == cap.target then
            self:activateControl(cap.target)
        end
        self.capture = nil
    end
    return true
end

function HUD:_drawActorsV2()
    -- Premium ESP: compact, high-contrast, animated enemies + calm bot markers.
    -- The data pipeline is unchanged; this is a presentation-only layer.
    local d, f = self.renderer, self.features
    local w, h, s = self.width, self.height, self.uiScale
    local halfW = w * 0.5
    local now = self.lastTime or 0
    -- Dynamic presentation: targets farther away use a smaller footprint.
    -- When the local player is aiming/scoped, aggressively compact the target
    -- frame/card while retaining a readable health strip.
    local scoped = self.playerAiming == true

    local function line(x1,y1,x2,y2,r,g,b,a,t)
        d.line(x1,y1,x2,y2,r,g,b,a,t)
    end

    local function cornerBox(cx, top, bw, bh, r,g,b, alpha, thick, cut)
        cut = cut or 10 * s
        local x = cx - bw * .5
        local y = top
        local right = x + bw
        local bottom = y + bh
        local len = min(cut, bw*.28, bh*.28)
        line(x,y,x+len,y,r,g,b,alpha,thick)
        line(x,y,x,y+len,r,g,b,alpha,thick)
        line(right-len,y,right,y,r,g,b,alpha,thick)
        line(right,y,right,y+len,r,g,b,alpha,thick)
        line(x,bottom-len,x,bottom,r,g,b,alpha,thick)
        line(x,bottom,x+len,bottom,r,g,b,alpha,thick)
        line(right-len,bottom,right,bottom,r,g,b,alpha,thick)
        line(right,bottom-len,right,bottom,r,g,b,alpha,thick)
    end

    local function miniBar(x,y,bw,bh,value,r,g,b)
        d.rect(x,y,bw,bh,0.015,0.02,0.03,0.72,true,2)
        if value > 0 then d.rect(x,y,bw*value,bh,r,g,b,0.95,true,2) end
    end

    local function distanceScale(meters)
        -- 1.0 at close range, smoothly falls off with distance, never
        -- disappearing completely so the overlay remains useful at range.
        local d0 = clamp(tonumber(meters) or 0, 0, 300)
        local t = clamp((d0 - 8) / 292, 0, 1)
        local eased = t * t * (3 - 2 * t)
        return 1.0 - 0.72 * eased
    end

    for i = 1, self.count do
        local row = self.records[i]
        local enemy = not row.bot
        local r,g,b = enemy and 1 or 0.08, enemy and 0.22 or 0.88, enemy and 0.30 or 1.0
        local hx, hy, fx, fy = row.headX, row.headY, row.feetX, row.feetY
        local head = hx and hy and hx >= 0 and hy >= 0 and hx <= w and hy <= h
        local feet = fx and fy and fx >= 0 and fy >= 0 and fx <= w and fy <= h

        if head then
            local baseBodyH = feet and max(36*s, fy-hy) or 96*s
            local scale = distanceScale(row.distance)
            if scoped then scale = scale * 0.34 end
            local bodyH = baseBodyH * scale
            local bodyW = clamp(bodyH * 0.36, 10*s, 78*s)
            local top = hy - bodyH*0.04
            local pulse = 0.5 + 0.5*sin(now*(enemy and 3.2 or 1.5) + i*0.73)

            -- Very subtle focus halo: enemies breathe/pulse, bots stay quiet.
            if enemy then
                d.circle(hx, hy + bodyH*.38, max(10*s, bodyW*.42), r,g,b,0.055 + pulse*0.035,false,1.5*s)
            end

            -- Optional snap lines remain, but are thinner and less intrusive.
            if (row.bot and f.botHeadLines) or ((not row.bot) and f.enemyHeadLines) then
                local a = enemy and (0.42 + pulse*0.20) or 0.28
                line(halfW, 8*s, hx, hy, r,g,b,a, max(1,1.2*s))
            end

            -- Enemy = premium tactical brackets; Bot = simple diamond marker.
            if enemy then
                cornerBox(hx, top, bodyW, bodyH, r,g,b,0.90 + pulse*0.08,max(1.3,1.7*s),10*s)
                -- second micro-frame gives a polished layered target-lock look
                cornerBox(hx, top+3*s, bodyW+5*s, bodyH-6*s, r,g,b,0.22,max(1,0.9*s),7*s)
                d.circle(hx, hy, 3.5*s, r,g,b,0.95,true)
                d.circle(hx, hy, 7*s, r,g,b,0.22 + pulse*0.10,false,max(1,1*s))
            else
                local rr = max(8*s, bodyW*.22)
                line(hx, hy-rr, hx+rr, hy, r,g,b,0.86,1.5*s)
                line(hx+rr, hy, hx, hy+rr, r,g,b,0.86,1.5*s)
                line(hx, hy+rr, hx-rr, hy, r,g,b,0.86,1.5*s)
                line(hx-rr, hy, hx, hy-rr, r,g,b,0.86,1.5*s)
                d.circle(hx, hy, 2.5*s, r,g,b,0.9,true)
            end

            -- Compact information card. Enemy card has a small threat notch; bot is plain.
            local cardScale = scale
            local pw = (enemy and 154 or 136) * s * cardScale
            local ph = (enemy and 39 or 32) * s * cardScale
            if scoped then
                -- Keep the card out of the sight picture while preserving a
                -- stronger health indicator.
                pw = (enemy and 154 or 136) * s * 0.38
                ph = (enemy and 39 or 32) * s * 0.38
            end
            local left = hx - pw*.5
            local cardY = max(6*s, top - ph - 5*s)
            if left < 5*s then left = 5*s elseif left+pw > w-5*s then left=w-5*s-pw end

            if scoped then
                -- Scoped mode: compact translucent tag, minimal text, readable HP.
                d.rect(left, cardY, pw, ph, 0.018,0.024,0.042, enemy and 0.54 or 0.46,true,4)
                d.rect(left, cardY, max(2*s, 3*s*0.38), ph, r,g,b,0.88,true,1)
                local barH = max(2.2*s, 3.2*s)
                miniBar(left + 5*s, cardY + ph - barH - 3*s,
                    max(8*s, pw - 10*s), barH, row.health, r,g,b)
            else
                d.rect(left+2*s, cardY+2*s, pw, ph, 0,0,0,0.22,true,6)
                d.rect(left, cardY, pw, ph, 0.018,0.024,0.042, enemy and 0.91 or 0.78,true,6)
                d.rect(left, cardY, 4*s*cardScale, ph, r,g,b,0.98,true,2)
                if enemy then
                    d.rect(left+4*s*cardScale, cardY, pw-4*s*cardScale, max(1*s, 2*s*cardScale),
                        r,g,b,0.32 + pulse*0.16,true,2)
                end

                if d.textBox then
                    local title = enemy and row.name or ('BOT  ' .. row.name)
                    local font = max(6*s, 11*s*cardScale)
                    d.textBox(left+10*s*cardScale, cardY+3*s*cardScale,
                        max(8*s, pw-20*s*cardScale), 15*s*cardScale,
                        title, font, 1,1,1,0.96,'left')
                    d.textBox(left+10*s*cardScale, cardY+18*s*cardScale,
                        max(8*s, 58*s*cardScale), 13*s*cardScale,
                        row.distanceLabel, max(6*s, 9.5*s*cardScale), r,g,b,0.95,'left')
                    d.textBox(left+70*s*cardScale, cardY+18*s*cardScale,
                        max(8*s, 48*s*cardScale), 13*s*cardScale,
                        row.healthLabel, max(6*s, 9.5*s*cardScale), 1,1,1,0.82,'left')
                end
                miniBar(left+10*s*cardScale, cardY+ph-max(3*s, 3*s*cardScale),
                    max(8*s, pw-20*s*cardScale), max(1.5*s, 3*s*cardScale), row.health, r,g,b)
            end

            -- Low-health emphasis only for enemies; no constant flashing.
            if enemy and row.health < 0.25 then
                local warn = 0.45 + 0.35*(0.5+0.5*sin(now*5.0+i))
                line(left, cardY+ph+2*s, left+pw, cardY+ph+2*s, r,g,b,warn,max(1,1.2*s))
            end
        end

        if feet and ((row.bot and f.botFeetLines) or ((not row.bot) and f.enemyFeetLines)) then
            line(halfW, h-22*s, fx, fy, r,g,b, enemy and 0.38 or 0.24, max(1,1.1*s))
        end
    end
end

function HUD:_drawCompass()
    local d, s = self.renderer, self.uiScale
    local cx, cy = self.width * 0.5, 72 * s
    local half = min(247 * s, self.width * 0.30)
    d.line(cx - half, cy, cx + half, cy, 1, 1, 1, 0.28, s)
    local degrees = self.yaw * 180 / pi
    for tick = floor((degrees - 120) / 15), math.ceil((degrees + 120) / 15) do
        local angle = tick * 15
        local x = cx + (angle - degrees) * 2 * s
        if abs(x - cx) <= half then
            local cardinal = (tick % 6) == 0
            d.line(x, cy - 16 * s, x, cy - (cardinal and 4 or 9) * s, 1, 1, 1, cardinal and .65 or .32, s)
            if cardinal then
                local names = { 'N', 'E', 'S', 'W' }
                boxed(d, x - 10 * s, cy - 24 * s, 20 * s, 16 * s, names[(tick // 6) % 4 + 1], 11 * s, 1, 1, 1, .86, 'center')
            end
        end
    end
    d.line(cx, cy - 2 * s, cx - 4 * s, cy + 10 * s, 1, 1, 1, 1, 2 * s)
    d.line(cx - 4 * s, cy + 10 * s, cx + 4 * s, cy + 10 * s, 1, 1, 1, 1, 2 * s)
    d.line(cx + 4 * s, cy + 10 * s, cx, cy - 2 * s, 1, 1, 1, 1, 2 * s)
end

function HUD:_drawCountsV2()
    local d, f, s = self.renderer, self.features, self.uiScale
    local count = (f.enemyCount and 1 or 0) + (f.botCount and 1 or 0)
    local bw, bh, gap = 120 * s, 32 * s, 24 * s
    local x = (self.width - count * bw - max(0, count - 1) * gap) * .5
    local y = 8 * s
    local function badge(label, value, bot)
        local r, g, b = 1, .24, .26
        if bot then r, g, b = 0, .91, 1 end
        d.rect(x, y, bw, bh, .035, .045, .06, .83, true, 1)
        d.rect(x, y, 4 * s, bh, r, g, b, 1, true, 1)
        boxed(d, x + 12 * s, y + 6 * s, 76 * s, 20 * s, label, 14 * s, 1, 1, 1, 1, 'left')
        boxed(d, x + 89 * s, y + 2 * s, 26 * s, 28 * s, value, 25 * s, r, g, b, 1, 'center')
        x = x + bw + gap
    end
    if f.enemyCount then badge('ENEMIES', self.enemyNumber, false) end
    if f.botCount then badge('BOTS', self.botNumber, true) end
    if self.totalOverflow > 0 or not self.overflowExact then
        boxed(d, self.width * .5 - 65 * s, 43 * s, 130 * s, 16 * s, self.limitLabel, 10 * s, 1, .85, .2, 1, 'center')
    end
end

function HUD:_drawEdges()
    if not self.features.distance then return end
    local left, right, behind
    local co, sy = cos(self.yaw), sin(self.yaw)
    for i = 1, self.count do
        local row = self.records[i]
        local projected = row.headX and row.headY
        local outside = projected and not inside(row.headX, row.headY, 0, 0, self.width, self.height)
        local ahead = row.dx * sy + row.dy * co
        if ahead < 0 then
            if not behind or row.distance < behind.distance then behind = row end
        elseif outside then
            local side = row.dx * co - row.dy * sy
            if side < 0 then
                if not left or row.distance < left.distance then left = row end
            elseif not right or row.distance < right.distance then right = row end
        end
    end
    local d, s = self.renderer, self.uiScale
    local function arrow(row, isLeft, rear)
        if not row then return end
        local r, g, b = 1, .24, .26
        if row.bot then r, g, b = 0, .91, 1 end
        if rear then
            local cx, cy = self.width * .5, self.height - 9 * s
            d.line(cx, cy, cx - 8 * s, cy - 12 * s, r, g, b, 1, 2 * s)
            d.line(cx - 8 * s, cy - 12 * s, cx + 8 * s, cy - 12 * s, r, g, b, 1, 2 * s)
            d.line(cx + 8 * s, cy - 12 * s, cx, cy, r, g, b, 1, 2 * s)
            d.rect(cx - 74 * s, cy - 39 * s, 148 * s, 23 * s, .025, .03, .04, .88, true, 1)
            boxed(d, cx - 68 * s, cy - 37 * s, 75 * s, 19 * s, 'BEHIND', 11 * s, 1, 1, 1, 1, 'left')
            boxed(d, cx + 7 * s, cy - 37 * s, 62 * s, 19 * s, row.distanceLabel, 12 * s, 1, 1, 1, 1, 'right')
            return
        end
        local cy = self.height * .5
        local tip = isLeft and 12 * s or self.width - 12 * s
        local back = tip + (isLeft and 18 * s or -18 * s)
        d.line(tip, cy, back, cy - 18 * s, r, g, b, 1, 2 * s)
        d.line(back, cy - 18 * s, back, cy + 18 * s, r, g, b, 1, 2 * s)
        d.line(back, cy + 18 * s, tip, cy, r, g, b, 1, 2 * s)
        local x = isLeft and back + 8 * s or back - 76 * s
        d.rect(x, cy - 12 * s, 68 * s, 24 * s, .025, .03, .04, .88, true, 1)
        boxed(d, x + 4 * s, cy - 10 * s, 60 * s, 20 * s, row.distanceLabel, 13 * s, 1, 1, 1, 1, 'center')
    end
    arrow(left, true) arrow(right, false) arrow(behind, false, true)
end

-- ========================================================================
-- PREMIUM MENU — full 1.lua ShayanPremiumUI style
-- ========================================================================
function HUD:_drawMenu()
    local d=self.renderer
    if d.beginMenu then d.beginMenu() end
    local s,t=self.panelScale,self.lastTime or 0
    local pulse=0.5+0.5*math.sin(t*1.25)
    local gold={1.00,0.79,0.08}
    local green={0.09,0.96,0.19}
    local red={0.97,0.07,0.10}
    local white={0.99,0.98,0.96}
    local muted={0.74,0.77,0.79}
    local ink={0.013,0.015,0.018}
    local function box(x,y,w,h,r,g,b,a,z) d.rect(x,y,w,h,r,g,b,a or 1,true,z or 5) end
    local function line(x1,y1,x2,y2,r,g,b,a,width) d.line(x1,y1,x2,y2,r,g,b,a or 1,width or 1) end
    local function label(x,y,w,h,v,size,c,align)
        d.textBox(x,y,w,h,tostring(v),size,c[1],c[2],c[3],1,align or 'left')
    end

    -- Compact launcher: same red/black/gold artwork family as the portal.
    local bx,by,bw,bh=self.buttonX,self.buttonY,self.buttonW,self.buttonH
    local bs=bw/132
    box(bx+3*bs,by+4*bs,bw,bh,0,0,0,0.52,1)
    box(bx,by,bw,bh,0.02,0.02,0.03,0.99,3)
    box(bx,by,bw,3*bs,red[1],red[2],red[3],0.95,4)
    box(bx,by,4*bs,bh,gold[1],gold[2],gold[3],1,5)
    box(bx,by+bh-3*bs,bw,3*bs,green[1],green[2],green[3],0.88,5)
    label(bx+15*bs,by+4*bs,bw-20*bs,19*bs,'SHAYAN',12*bs,white)
    label(bx+15*bs,by+21*bs,bw-20*bs,12*bs,self.open and 'CLOSE MENU' or 'OPEN MENU',6.8*bs,gold)
    if not self.open then if d.endMenu then d.endMenu() end return end

    local x,y,W,H=self.panelX,self.panelY,self.panelW,self.panelH
    local navW=self.navWidth*s
    local content=x+navW
    local cw=W-navW
    local headerH=self.headerHeight*s
    -- Red lightning outer rails with shimmering gold and emerald edges.
    box(x+10*s,y+12*s,W,H,0,0,0,0.55,1)
    box(x,y,W,H,red[1],red[2],red[3],0.96,2)
    box(x+3*s,y+3*s,W-6*s,H-6*s,ink[1],ink[2],ink[3],0.995,3)
    box(x+4*s,y+4*s,W-8*s,headerH-4*s,0.095,0.014,0.020,1,4)
    box(x+4*s,y+headerH-3*s,W-8*s,3*s,gold[1],gold[2],gold[3],1,7)
    box(x+5*s,y+H-5*s,W-10*s,3*s,green[1],green[2],green[3],0.95,7)
    box(x+W-6*s,y+headerH,3*s,H-headerH-3*s,green[1],green[2],green[3],0.95,7)
    -- Slim angular streaks (not a constantly animated heavy particle system).
    for i=1,4 do
        local yy=y+(12+i*9)*s
        line(x+(10+i*22)*s,yy,x+(30+i*22)*s,yy-5*s,
             red[1],red[2],red[3],0.26+0.09*pulse,1.1*s)
    end
    label(x+21*s,y+3*s,350*s,38*s,'SHAYAN MOD MENU',25*s,white)
    label(x+24*s,y+47*s,260*s,20*s,'PREMIUM CONTROL PANEL',9.5*s,gold)
    box(x+W-194*s,y+12*s,125*s,23*s,0.06,0.19,0.06,1,5)
    box(x+W-185*s,y+20*s,7*s,7*s,green[1],green[2],green[3],0.77+0.22*pulse,6)
    label(x+W-170*s,y+15*s,112*s,18*s,'VIP ACTIVE',8*s,green)
    local closeX,closeY=x+W-58*s,y+40*s
    box(closeX,closeY,42*s,30*s,0.28,0.015,0.020,1,7)
    box(closeX,closeY,42*s,2*s,red[1],red[2],red[3],1,8)
    label(closeX+2*s,closeY+4*s,38*s,23*s,'X',13*s,white,'center')

    box(x+5*s,y+headerH,navW-5*s,H-headerH-5*s,0.02,0.025,0.026,1,3)
    line(x+navW,y+headerH,x+navW,y+H-5*s,gold[1],gold[2],gold[3],0.65,2*s)
    local nav={{'v2','ESP','ESP FEATURES'}, {'aim','AIMBOT','TARGET CONTROL'},
               {'visual','VISUALS','COLOR DISPLAY'}}
    local navAccent={red,gold,green}
    for i,item in ipairs(nav) do
        local yy=y+(96+(i-1)*66)*s
        local active=self.page==item[1]
        local accent=navAccent[i]
        local nx=x+11*s
        local nw=(self.navWidth-22)*s
        box(nx,yy,nw,50*s,
             active and accent[1]*0.25 or 0.045,
             active and accent[2]*0.27 or 0.051,
             active and accent[3]*0.30 or 0.053,1,6)
        box(nx,yy,nw,2*s,accent[1],accent[2],accent[3],0.7,7)
        if active then box(nx,yy,5*s,50*s,accent[1],accent[2],accent[3],1,8) end
        label(nx+14*s,yy+5*s,nw-20*s,26*s,item[2],14*s,active and white or muted)
        label(nx+14*s,yy+31*s,nw-20*s,15*s,item[3],5.7*s,active and gold or muted)
    end
    local footerY=y+H-72*s
    box(x+12*s,footerY,(self.navWidth-24)*s,50*s,0.055,0.085,0.037,1,5)
    box(x+12*s,footerY,3*s,50*s,green[1],green[2],green[3],1,6)
    label(x+22*s,footerY+6*s,(self.navWidth-33)*s,20*s,'SHAYAN VIP',10*s,gold)
    label(x+22*s,footerY+29*s,(self.navWidth-33)*s,17*s,'@SHAYAN_OWNER',6.4*s,white)

    local heading=({v2='ESP FEATURES',aim='AIMBOT CONTROL',visual='VISUAL SETTINGS'})[self.page]
    local desc=({v2='DISPLAY MODULE',aim='TARGET MODULE',visual='COLOR CUSTOMIZATION'})[self.page]
    box(content+16*s,y+91*s,cw-32*s,46*s,0.036,0.10,0.042,1,5)
    box(content+16*s,y+91*s,4*s,46*s,green[1],green[2],green[3],1,6)
    label(content+30*s,y+94*s,cw-60*s,26*s,heading or 'CONTROLS',14.5*s,gold)
    label(content+30*s,y+119*s,cw-60*s,14*s,desc or 'OPTIONS',6.8*s,white)
    line(content+17*s,y+143*s,x+W-17*s,y+143*s,gold[1],gold[2],gold[3],0.54,1.25*s)
    local function toggleRow(name,ry,enabled,rh)
        local rowX=content+16*s
        local rowW=cw-32*s
        local hh=rh*s
        box(rowX,ry,rowW,hh,0.036,enabled and 0.091 or 0.044,
            enabled and 0.050 or 0.052,1,5)
        box(rowX,ry,3*s,hh,enabled and green[1] or red[1],
            enabled and green[2] or red[2],enabled and green[3] or red[3],0.90,6)
        label(rowX+13*s,ry+4*s,rowW-117*s,hh-8*s,name,9.3*s,enabled and white or muted)
        local swX,swY=rowX+rowW-42*s,ry+(hh-17*s)/2
        box(swX,swY,34*s,17*s,
            enabled and 0.08 or 0.17,enabled and 0.84 or 0.18,
            enabled and 0.15 or 0.18,1,7)
        d.circle(swX+(enabled and 25 or 9)*s,swY+8.5*s,5.6*s,1,1,1,1,true)
        label(rowX+rowW-92*s,ry+5*s,41*s,hh-9*s,
            enabled and 'ON' or 'OFF',8*s,enabled and green or muted,'right')
    end
    if self.page=='v2' then
        for i=1,#ROWS do
            toggleRow(ROWS[i][2],y+(157+(i-1)*self.rowHeight)*s,
                self.features[ROWS[i][1]],self.rowHeight)
        end
    elseif self.page=='aim' then
        for i=1,#AIM_KEYS do
            if AIM_SUPPORTED[AIM_KEYS[i]] then
                toggleRow(AIMS[i],y+(160+(i-1)*32)*s,self.aim[AIM_KEYS[i]],28)
            end
        end
        toggleRow('Show Aim Circle',y+390*s,self.aim.circle,28)
        toggleRow('Small Crosshair',y+422*s,self.aim.smallCrosshair,28)
        toggleRow('Bypass',y+454*s,self.aim.bypass,28)
    elseif self.page=='visual' then
        toggleRow('Tablet View 120',y+160*s,self.visual.ipadView,30)
        toggleRow('Behind-Wall Color',y+194*s,self.visual.wallHack,30)
        local sections={'VISIBLE COLOR','BEHIND WALL COLOR'}
        for category=1,2 do
            local py=y+(261+(category-1)*82)*s
            label(content+20*s,py-19*s,cw-40*s,17*s,sections[category],8.0*s,gold)
            for i=1,10 do
                local px=content+(20+(i-1)*31)*s
                local selected=(category==1 and self.visual.visibleColor or self.visual.occludedColor)==i
                local r,g,b=PALETTE[i][2],PALETTE[i][3],PALETTE[i][4]
                if selected then box(px-2*s,py-2*s,29*s,29*s,gold[1],gold[2],gold[3],0.56,5) end
                box(px,py,25*s,25*s,r,g,b,selected and 1 or 0.65,6)
                if selected then d.circle(px+12.5*s,py+12.5*s,3*s,1,1,1,1,true) end
            end
        end
    end
    if d.endMenu then d.endMenu() end
end
function HUD:draw(width, height, now)
    if not self:resize(width, height) then return false end
    local validTime = finite(now)
    if validTime then
        if (self.lastTime and now < self.lastTime) or (self.snapshotAt and now - self.snapshotAt > self.staleAfter) then
            self:_clearActors(true)
        end
        self.lastTime = now
    end
    self:_drawMenu()
    if validTime and self.snapshotAt and not self.stale and self.aim.circle and
        (self.aim.force or self.aim.assistant or self.aim.sniper or self.aim.mortar) then
        self.renderer.circle(self.width * .5, self.height * .5, 105 * self.uiScale, 1, 1, 1, 1, false, max(2, 3 * self.uiScale))
    end
    if validTime and self.snapshotAt and not self.stale and self.features.enabled then
        self:_drawActorsV2()
        self:_drawEdges()
        if self.features.compass then self:_drawCompass() end
        self:_drawCountsV2()
    end
    return true
end

return HUD
end)()

-- ========================================================================
-- 3. NATIVE UMG RENDERER AND TOUCH INPUT
-- ========================================================================

local ShayanUMGAdapter = (function()
local Adapter = {}
Adapter.__index = Adapter
local abs, min, max, sqrt = math.abs, math.min, math.max, math.sqrt
local floor, huge = math.floor, math.huge
local pi = math.pi
local function finite(v) return type(v) == 'number' and v == v and v ~= huge and v ~= -huge end
local function field(o, k)
    if o == nil then return nil end
    local ok, v = pcall(function() return o[k] end)
    if ok then return v end
end
local function method(o, k)
    local f = field(o, k)
    return type(f) == 'function' and f or nil
end
local function invoke(o, k, ...)
    local f = method(o, k)
    if not f then return false, 'Missing native method: ' .. k end
    return pcall(f, o, ...)
end
local function construct(f, ...)
    if f == nil then return nil end
    local ok, v = pcall(f, ...)
    if ok then return v end
end
local function bounded(v, default, lo, hi)
    return finite(v) and floor(max(lo, min(hi, v))) or default
end
local KEYS = { 'enabled', 'enemyCount', 'botCount',
    'health', 'names', 'distance', 'enemyHeadLines', 'enemyFeetLines', 'botHeadLines', 'botFeetLines' }
local CIRCLE = {}
for i = 0, 12 do CIRCLE[i + 1] = { math.cos(i * 2 * pi / 12), math.sin(i * 2 * pi / 12) } end

function Adapter:_error(message, fatal)
    self.error = tostring(message):sub(1, 220)
    self.errors = self.errors + 1
    if fatal then self.failed = true end
end
function Adapter:_warn(message)
    self.warning = tostring(message):sub(1, 220)
    self.warnings = self.warnings + 1
end
function Adapter:_write(o, k, ...)
    local ok, err = invoke(o, k, ...)
    if not ok then self:_error(err, true) end
    return ok
end
function Adapter:_isValid(o)
    if o == nil then return false end
    local valid = field(self.env.slua, 'isValid')
    if type(valid) == 'function' then
        local ok, v = pcall(valid, o)
        if ok and v == true then return true end
    end
    local game = self.env.Game
    if method(game, 'IsValid') then
        local ok, v = invoke(game, 'IsValid', o)
        return ok and v == true
    end
    if type(valid) == 'function' then return false end
    return true
end
function Adapter:_vector(x, y) return construct(self.Vector, x, y) or { X = x, Y = y } end
function Adapter:_color(r, g, b, a) return construct(self.Linear, r, g, b, a) or { R = r, G = g, B = b, A = a } end
function Adapter:_visible(node, wanted, hit)
    if node.visible == wanted then return true end
    local value = wanted and (hit and self.visibility.Visible or self.visibility.SelfHitTestInvisible) or self.visibility.Collapsed
    if self:_write(node.widget, 'SetWidgetVisibility', value) then node.visible = wanted return true end
    return false
end
function Adapter:_position(node, x, y)
    if node.x == x and node.y == y then return true end
    if self:_write(node.slot, 'SetPosition', self:_vector(x, y)) then node.x, node.y = x, y return true end
    return false
end
function Adapter:_size(node, w, h)
    if node.w == w and node.h == h then return true end
    if self:_write(node.slot, 'SetSize', self:_vector(w, h)) then node.w, node.h = w, h return true end
    return false
end
function Adapter:_z(node, z)
    if node.z == z then return true end
    if self:_write(node.slot, 'SetZOrder', z) then node.z = z return true end
    return false
end
function Adapter:_remove(node)
    if not node then return end
    node.removed = true
    for i = 1, #(node.bindings or {}) do
        local item = node.bindings[i]
        item.active = false
        if item.handle ~= nil and method(item.delegate, 'Remove') then
            local ok, err = invoke(item.delegate, 'Remove', item.handle)
            if not ok then self:_warn(err) end
        end
    end
    node.bindings = {}
    invoke(node.widget, 'RemoveFromParent')
    invoke(node.widget, 'ConditionalBeginDestroy')
end
function Adapter:_newNative(path, parent, input)
    if self.disposed or self.failed or self.total >= self.maxWidgets or self.createdThisFrame >= self.createBudget then
        self.deferred = self.deferred + 1
        return nil
    end
    self.createdThisFrame = self.createdThisFrame + 1
    local ok, widget = invoke(self.env.CGame, 'NewObjectFromPath', path, parent)
    if not ok or not self:_isValid(widget) then
        self:_error('UMG widget creation failed: ' .. path, not input)
        if input then self.inputFailed = true end
        return nil
    end
    local slotOK, slot = invoke(parent, 'AddChildToCanvas', widget)
    if not slotOK or not slot then
        invoke(widget, 'RemoveFromParent')
        invoke(widget, 'ConditionalBeginDestroy')
        self:_error('UMG canvas slot creation failed', not input)
        if input then self.inputFailed = true end
        return nil
    end
    local node = { widget = widget, slot = slot, bindings = {} }
    self.total = self.total + 1
    self.owned[#self.owned + 1] = node
    if not self:_write(slot, 'SetAutoSize', false) then return nil end
    self:_visible(node, false, input)
    return node
end

function Adapter.new(parentCanvas, env)
    env = type(env) == 'table' and env or _G
    local enums = field(env.UEnums, 'ESlateVisibility')
    if not enums or enums.Collapsed == nil or enums.SelfHitTestInvisible == nil or enums.Visible == nil then
        return nil, 'UEnums.ESlateVisibility is unavailable'
    end
    if not method(env.CGame, 'NewObjectFromPath') or not method(parentCanvas, 'AddChildToCanvas') then
        return nil, 'CGame widget factory or parent CanvasPanel is unavailable'
    end
    local cfg = type(env.ESPAdapterConfig) == 'table' and env.ESPAdapterConfig or {}
    local self = setmetatable({
        env = env, parent = parentCanvas, visibility = enums, owned = {},
        pools = { line = {}, rect = {}, text = {}, dot = {} },
        cursors = {}, total = 0, frame = 0, serial = 0, createdThisFrame = 0,
        errors = 0, warnings = 0, deferred = 0, droppedCommands = 0,
        maxWidgets = bounded(cfg.maxWidgets, 4096, 4, 4096),
        createBudget = bounded(cfg.createBudget, 16, 1, 128),
        actorGroups = {}, actorByKey = {}, actorFree = {},
        controls = {}, touchStates = {}, touchPositions = {},
        inputSupported = false, dragSupported = false, bindingsVerified = false,
        touchTupleObserved = false, touchDownObserved = false, touchMovementObserved = false,
        menuCaptureObserved = false, menuMovementObserved = false,
        touchSamples = 0, menuCaptures = 0, menuMoves = 0,
        textMeasured = 0, textClipped = 0, textUnverified = 0
    }, Adapter)
    local function dependency(name, short, long)
        local v = env[name]
        if v then return v end
        if type(env.import) == 'function' then
            local ok, a = pcall(env.import, short)
            if ok and a then return a end
            if long then
                ok, a = pcall(env.import, long)
                if ok then return a end
            end
        end
    end
    self.Vector = dependency('FVector2D', 'Vector2D')
    self.Linear = dependency('FLinearColor', 'LinearColor')
    self.Slate = dependency('FSlateColor', 'SlateColor', '/Script/SlateCore.SlateColor')
    if not self:_isValid(parentCanvas) then return nil, 'Parent CanvasPanel is invalid' end
    local root = self:_newNative('/Script/UMG.CanvasPanel', parentCanvas)
    if not root or self.failed then
        self:dispose()
        return nil, self.error or 'Owned canvas unavailable'
    end
    self.root = root
    self:_position(root, 0, 0)
    self:_z(root, 10000)
    self:_visible(root, true)
    if self.failed then
        self:dispose()
        return nil, self.error
    end
    self.renderer = {
        line = function(...) return self:_line(...) end,
        rect = function(...) return self:_rect(...) end,
        circle = function(...) return self:_circle(...) end,
        text = function(...) return self:_text(...) end,
        textBox = function(...) return self:_textBox(...) end,
        beginMenu = function() self.inMenu = true self.menuSeen = true end,
        endMenu = function() self.inMenu = false end,
        beginActor = function(...) return self:_beginActor(...) end,
        endActor = function() self.currentGroup = nil end
    }
    return self
end

function Adapter:valid()
    return not self.disposed and not self.failed and self:_isValid(self.parent)
        and self.root ~= nil and self:_isValid(self.root.widget)
end

function Adapter:setViewportOrigin(x, y)
    if not finite(x) or not finite(y) or not self:valid() then return false end
    return self:_position(self.root, x, y)
end

function Adapter:beginFrame()
    if self.disposed then return false end
    self.frame = self.frame + 1
    self.serial = 0
    self.createdThisFrame = 0
    self.deferred = 0
    self.droppedCommands = 0
    self.inMenu = false
    self.menuSeen = false
    self.menuDropped = 0
    self.currentGroup = nil
    self.textMeasured = 0
    self.textClipped = 0
    self.textUnverified = 0
    for k in pairs(self.pools) do self.cursors[k] = 0 end
    return self:valid()
end

function Adapter:_beginActor(key, x, y, w, h)
    if self.disposed or self.failed or self.currentGroup or self.inMenu then return false end
    if not ((type(key) == 'string' and #key > 0) or finite(key)) or not (finite(x) and finite(y)) then return false end
    w = finite(w) and w or self.root.w or 1280
    h = finite(h) and h or self.root.h or 720
    if w <= 0 or h <= 0 then return false end
    local group = self.actorByKey[key]
    if not group then
        local free = self.actorFree
        group = free[#free]
        if group then
            free[#free] = nil
            group.free = false
        else
            group = self:_newNative('/Script/UMG.CanvasPanel', self.root.widget)
            if not group then return false end
            group.pools = { line = {}, rect = {}, text = {}, dot = {} }
            group.cursors = {}
            self.actorGroups[#self.actorGroups + 1] = group
        end
        group.key = key
        self.actorByKey[key] = group
    end
    group.used = self.frame
    group.serial = 0
    for kind in pairs(group.pools) do group.cursors[kind] = 0 end
    self.serial = self.serial + 1
    self:_position(group, x, y)
    self:_size(group, w, h)
    self:_z(group, self.serial)
    self:_visible(group, true)
    if self.failed then return false end
    self.currentGroup = group
    return true
end

function Adapter:_borrow(kind)
    if self.disposed or self.failed then return nil end
    local owner = self.currentGroup or self
    local index = (owner.cursors[kind] or 0) + 1
    owner.cursors[kind] = index
    owner.serial = owner.serial + 1
    local pool = owner.pools[kind]
    local node = pool[index]
    if not node then
        local path = (kind == 'text' or kind == 'dot') and '/Script/UMG.TextBlock' or '/Script/UMG.Border'
        node = self:_newNative(path, self.currentGroup and self.currentGroup.widget or self.root.widget)
        if not node then
            self.droppedCommands = self.droppedCommands + 1
            if self.inMenu then self.menuDropped = self.menuDropped + 1 end
            return nil
        end
        pool[index] = node
        if kind == 'line' then
            self:_write(node.widget, 'SetRenderTransformPivot', self:_vector(0, 0.5))
        elseif kind == 'text' or kind == 'dot' then
            self:_write(node.widget, 'SetRenderTransformPivot', self:_vector(0, 0))
            if method(node.widget, 'SetAutoWrapText') then invoke(node.widget, 'SetAutoWrapText', false) end
            local clipping = field(field(self.env.UEnums, 'EWidgetClipping'), 'ClipToBounds')
            if clipping ~= nil then node.clipped = invoke(node.widget, 'SetClipping', clipping) == true end
        end
    end
    node.used = self.frame
    self:_z(node, (self.inMenu and 10000 or 0) + owner.serial)
    self:_visible(node, true)
    return node
end

function Adapter:_tint(node, r, g, b, a, text)
    if node.r == r and node.g == g and node.b == b and node.a == a then return end
    local color = self:_color(r, g, b, a)
    if text then color = construct(self.Slate, color) or color end
    if self:_write(node.widget, text and 'SetColorAndOpacity' or 'SetBrushColor', color) then
        node.r, node.g, node.b, node.a = r, g, b, a
    end
end
local function colorOK(r, g, b, a) return finite(r) and finite(g) and finite(b) and finite(a) and a > 0 end
function Adapter:_line(x1, y1, x2, y2, r, g, b, a, thickness)
    if not (finite(x1) and finite(y1) and finite(x2) and finite(y2) and finite(thickness)
        and thickness > 0 and colorOK(r, g, b, a)) then return false end
    local dx, dy = x2 - x1, y2 - y1
    local length = sqrt(dx * dx + dy * dy)
    if not finite(length) or length < 0.01 then return false end
    local node = self:_borrow('line')
    if not node then return false end
    self:_position(node, x1, y1 - thickness * 0.5)
    self:_size(node, length, thickness)
    local angle = math.atan(dy, dx) * 180 / pi
    if node.angle ~= angle and self:_write(node.widget, 'SetRenderAngle', angle) then node.angle = angle end
    self:_tint(node, r, g, b, a)
    return not self.failed
end
function Adapter:_rect(x, y, w, h, r, g, b, a, filled, thickness)
    if not (finite(x) and finite(y) and finite(w) and finite(h) and w > 0 and h > 0 and colorOK(r, g, b, a)) then return false end
    thickness = finite(thickness) and max(0.1, thickness) or 1
    if not filled then
        self:_line(x, y, x + w, y, r, g, b, a, thickness)
        self:_line(x + w, y, x + w, y + h, r, g, b, a, thickness)
        self:_line(x + w, y + h, x, y + h, r, g, b, a, thickness)
        self:_line(x, y + h, x, y, r, g, b, a, thickness)
        return not self.failed
    end
    local node = self:_borrow('rect')
    if not node then return false end
    self:_position(node, x, y)
    self:_size(node, w, h)
    self:_tint(node, r, g, b, a)
    return not self.failed
end
function Adapter:_font(node, size)
    size = max(1, floor(size + 0.5))
    if node.fontSize == size then return true end
    if node.fontUnsupported then return false end
    local font = field(node.widget, 'Font')
    if font then
        local sized = pcall(function() font.Size = size end)
        if sized then
            local assigned = pcall(function() node.widget.Font = font end)
            if assigned then node.fontSize = size return true end
            if method(node.widget, 'SetFont') then
                local set = invoke(node.widget, 'SetFont', font)
                if set then node.fontSize = size return true end
            end
        end
    end
    node.fontUnsupported = true
    if not self.fontWarning then
        self.fontWarning = true
        self:_warn('Text size binding unavailable; retaining the widget default font')
    end
    return false
end
local function glyphCount(value)
    if utf8 and utf8.len then
        local ok, n = pcall(utf8.len, value)
        if ok and n then return n end
    end
    return #value
end
function Adapter:_textBox(x, y, w, h, value, size, r, g, b, a, align, kind)
    if not (finite(x) and finite(y) and finite(w) and finite(h) and w > 0 and h > 0
        and finite(size) and size > 0 and type(value) == 'string' and #value > 0
        and colorOK(r, g, b, a)) then return false end
    local node = self:_borrow(kind or 'text')
    if not node then return false end
    local changed = node.text ~= value or node.requestedSize ~= size or node.boxW ~= w or node.boxH ~= h
    self:_font(node, size)
    self:_tint(node, r, g, b, a, true)
    if node.text ~= value and self:_write(node.widget, 'SetText', value) then node.text = value end
    if changed or (node.layoutPending and self.frame >= (node.nextLayoutTry or 0)) then
        if method(node.widget, 'ForceLayoutPrepass') then invoke(node.widget, 'ForceLayoutPrepass') end
        local ok, desired = invoke(node.widget, 'GetDesiredSize')
        local dw, dh = field(desired, 'X'), field(desired, 'Y')
        local measured = ok and finite(dw) and finite(dh) and dw > 0 and dh > 0
        node.layoutPending = not measured and method(node.widget, 'GetDesiredSize') ~= nil
        node.nextLayoutTry = self.frame + 3
        if not measured then
            local native = field(field(node.widget, 'Font'), 'Size')
            local estimate = finite(native) and max(native, size) or max(96, size)
            dw = max(1, glyphCount(value)) * estimate * 2
            dh = estimate * 2.5
        end
        local scale = min(1, w / dw, h / dh)
        if node.scale ~= scale then
            local scaled = invoke(node.widget, 'SetRenderScale', self:_vector(scale, scale))
            if scaled then node.scale = scale else scale = 1 end
        end
        if not node.scale then scale = 1 else scale = node.scale end
        if measured and dw * scale <= w + 0.001 and dh * scale <= h + 0.001 then
            node.textMode = 'measured'
            node.drawW, node.drawH = dw * scale, dh * scale
            self:_size(node, dw, dh)
        else
            self:_size(node, w / scale, h / scale)
            node.drawW, node.drawH = w, h
            node.textMode = node.clipped and 'clipped' or 'unverified'
        end
        node.requestedSize, node.boxW, node.boxH = size, w, h
    end
    local offset = align == 'right' and w - node.drawW or (align == 'center' and (w - node.drawW) * 0.5 or 0)
    self:_position(node, x + max(0, offset), y + max(0, (h - node.drawH) * 0.5))
    if node.textMode == 'measured' then self.textMeasured = self.textMeasured + 1
    elseif node.textMode == 'clipped' then self.textClipped = self.textClipped + 1
    else self.textUnverified = self.textUnverified + 1 end
    return not self.failed
end
function Adapter:_text(x, y, value, size, r, g, b, a)
    if type(value) ~= 'string' or not finite(size) or size <= 0 then return false end
    return self:_textBox(x, y, max(1, glyphCount(value)) * size * 1.5, size * 2.5, value, size, r, g, b, a, 'left')
end
function Adapter:_circle(x, y, radius, r, g, b, a, filled, thickness)
    if not (finite(x) and finite(y) and finite(radius) and radius > 0 and colorOK(r, g, b, a)) then return false end
    if filled then
        return self:_textBox(x - radius, y - radius, radius * 2, radius * 2, '●', radius * 2, r, g, b, a, 'center', 'dot')
    else
        thickness = finite(thickness) and max(0.1, thickness) or 1
        for i = 1, 12 do
            local p, q = CIRCLE[i], CIRCLE[i + 1]
            self:_line(x + p[1] * radius, y + p[2] * radius, x + q[1] * radius, y + q[2] * radius, r, g, b, a, thickness)
        end
    end
    return not self.failed
end

function Adapter:endFrame()
    if self.disposed then return false end
    self.currentGroup = nil
    for _, pool in pairs(self.pools) do
        for _, node in pairs(pool) do if node.used ~= self.frame then self:_visible(node, false) end end
    end
    for _, group in ipairs(self.actorGroups) do
        if group.used == self.frame then
            for _, pool in pairs(group.pools) do
                for _, node in pairs(pool) do if node.used ~= self.frame then self:_visible(node, false) end end
            end
        elseif not group.free then
            self:_visible(group, false)
            self.actorByKey[group.key] = nil
            group.key = nil
            group.free = true
            self.actorFree[#self.actorFree + 1] = group
        end
    end
    if self.failed or self.menuDropped > 0 or not self.inputSupported then self:_cancelInput() end
    return not self.failed
end

function Adapter:_bind(node, event, callback, required)
    local delegate = field(node.widget, event)
    local function failed(message)
        if required ~= false then
            self:_error(message, false)
            self.inputFailed = true
        else
            self:_warn(message)
        end
        return false
    end
    if not method(delegate, 'Add') then return failed('Native button delegate unavailable: ' .. event) end
    local item = { delegate = delegate, active = false }
    local guarded = function(...)
        if self.disposed or node.removed or not item.active then return end
        return callback(...)
    end
    local ok, handle = invoke(delegate, 'Add', guarded)
    if not ok then return failed('Could not bind native button delegate: ' .. event) end
    item.handle, item.active = handle, true
    node.bindings[#node.bindings + 1] = item
    return true
end

function Adapter:_button(name, z, clicked, pressed, released)
    if self.inputFailed then return nil end
    local node = self.controls[name]
    if node then return node end
    node = self:_newNative('/Script/UMG.Button', self.root.widget, true)
    if not node then return nil end
    local ok, err = invoke(node.widget, 'SetBackgroundColor', self:_color(1, 1, 1, 0))
    if not ok then
        self:_error(err, false)
        self.inputFailed = true
        return nil
    end
    self:_z(node, z)
    if clicked and not self:_bind(node, 'OnClicked', clicked) then return nil end
    if pressed or released then
        local pressOK = pressed and self:_bind(node, 'OnPressed', pressed, false)
        local releaseOK = released and self:_bind(node, 'OnReleased', released, false)
        node.dragBindingsSupported = pressOK == true and releaseOK == true
    end
    self.controls[name] = node
    return node
end

local function decodeTouch(a, b, c)
    if finite(a) and finite(b) and type(c) == 'boolean' then return a, b, c end
    if type(a) == 'boolean' and finite(b) and finite(c) then return b, c, a end
end

function Adapter:_touch(finger)
    if not method(self.pc, 'GetInputTouchState') then
        self.touchTupleAvailable = false
        self.dragSupported = false
        return nil
    end
    local ok, a, b, c
    if self.touchSignature == 4 then
        ok, a, b, c = invoke(self.pc, 'GetInputTouchState', finger, 0, 0, false)
    else
        ok, a, b, c = invoke(self.pc, 'GetInputTouchState', finger)
    end
    local x, y, down
    if ok then x, y, down = decodeTouch(a, b, c) end
    if x == nil and self.touchSignature == nil then
        ok, a, b, c = invoke(self.pc, 'GetInputTouchState', finger, 0, 0, false)
        if ok then x, y, down = decodeTouch(a, b, c) end
        if x ~= nil then self.touchSignature = 4 end
    elseif x ~= nil and self.touchSignature == nil then
        self.touchSignature = 1
    end
    if x == nil then
        self.touchTupleAvailable = false
        self.dragSupported = false
        return nil
    end
    if self.toCanvas then
        local converted, cx, cy = pcall(self.toCanvas, x, y)
        if not converted or not finite(cx) or not finite(cy) then
            self.touchTupleAvailable = false
            self.dragSupported = false
            return nil
        end
        x, y = cx, cy
    end
    self.touchTupleAvailable = true
    self.touchTupleObserved = true
    self.touchSamples = min(1000000, self.touchSamples + 1)
    if down then self.touchDownObserved = true end
    local previous = self.touchPositions[finger]
    if previous and previous.down and down and (previous.x ~= x or previous.y ~= y) then
        self.touchMovementObserved = true
    end
    if not previous then previous = {} self.touchPositions[finger] = previous end
    previous.x, previous.y, previous.down = x, y, down
    self.dragSupported = self.menuMovementObserved == true
    return x, y, down
end

function Adapter:_dragHit(x, y)
    if self.descriptors then
        local hit, highest
        for i = 1, min(#self.descriptors, 64) do
            local d = self.descriptors[i]
            if self:_descriptorValid(d) and x >= d.x and y >= d.y and x <= d.x + d.w and y <= d.y + d.h
                and (not highest or d.z >= highest) then hit, highest = d, d.z end
        end
        if not hit or hit.enabled == false then return false end
        if self.hud and self.hud.open and hit.action ~= 'button' then return true end
        return hit.drag == true
    end
    return self.hud and self.hud:_hit(x, y) == 'button'
end

function Adapter:_capture(finger, x, y)
    if self.active or not self.hud or not self:_dragHit(x, y) then return false end
    if self.hud:pointer('down', x, y, finger) then
        self.active = { id = finger, x = x, y = y, misses = 0 }
        self.menuCaptureObserved = true
        self.menuCaptures = min(1000000, self.menuCaptures + 1)
        self.suppressClick = true
        self.suppressUntil = nil
        self.pendingPress = false
        return true
    end
    return false
end

function Adapter:_pressed()
    if self.disposed or not self.hud or self.active then return end
    self.suppressClick = false
    self.pendingPress = true
    for finger = 0, 9 do
        local x, y, down = self:_touch(finger)
        if x == nil then break end
        if down and self:_capture(finger, x, y) then return end
    end
end

function Adapter:_released()
    self.pendingPress = false
    local active = self.active
    if not active or not self.hud then return end
    local x, y = self:_touch(active.id)
    self.hud:pointer('up', x or active.x, y or active.y, active.id)
    self.active = nil
    self.suppressUntil = self.frame + 2
end

function Adapter:_pollTouch()
    if self.suppressUntil and self.frame > self.suppressUntil then
        self.suppressClick = false
        self.suppressUntil = nil
    end
    if not self.active and not (self.hud and self.hud.open) then
        return
    end
    for finger = 0, 9 do
        local x, y, down = self:_touch(finger)
        if x == nil then
            if self.active and self.active.id == finger then
                self.active.misses = self.active.misses + 1
                if self.active.misses >= 3 then
                    self.hud:pointer('cancel', 0, 0, finger)
                    self.active = nil
                    self.suppressUntil = self.frame + 2
                end
            end
            break
        end
        local previous = self.touchStates[finger]
        self.touchStates[finger] = down
        if self.active and self.active.id == finger then
            self.active.misses = 0
            if down then
                local beforeX, beforeY = self.hud.buttonX, self.hud.buttonY
                self.active.x, self.active.y = x, y
                self.hud:pointer('move', x, y, finger)
                if self.hud.buttonX ~= beforeX or self.hud.buttonY ~= beforeY then
                    self.menuMovementObserved = true
                    self.dragSupported = true
                    self.menuMoves = min(1000000, self.menuMoves + 1)
                end
            else
                self.hud:pointer('up', x, y, finger)
                self.active = nil
                self.suppressUntil = self.frame + 2
            end
        elseif not self.active and down and previous ~= true then
            self:_capture(finger, x, y)
        end
    end
end

function Adapter:_cancelInput()
    if self.active and self.hud then self.hud:pointer('cancel', 0, 0, self.active.id) end
    self.active = nil
    self.pendingPress = false
    self.inputSupported = false
    self.dragSupported = false
    for _, node in pairs(self.controls) do self:_visible(node, false, true) end
end

function Adapter:_descriptorValid(d)
    return type(d) == 'table' and type(d.id) == 'string' and #d.id > 0 and #d.id <= 64
        and type(d.action) == 'string' and #d.action <= 96
        and finite(d.x) and finite(d.y) and finite(d.w) and finite(d.h) and d.w > 0 and d.h > 0
        and finite(d.z) and d.z >= 0 and d.z <= 99
        and (d.drag == nil or type(d.drag) == 'boolean') and (d.enabled == nil or type(d.enabled) == 'boolean')
end

function Adapter:_descriptorList()
    local ok, list = invoke(self.hud, 'getControls')
    if not ok or type(list) ~= 'table' or #list > 64 then
        if not self.descriptorWarning then
            self.descriptorWarning = true
            self:_warn('HUD controls must be an array with at most 64 entries')
        end
        self.descriptors = nil
        return nil
    end
    self.descriptors = list
    return list
end

function Adapter:_descriptorClick(id)
    local node = self.controls[id]
    if self.disposed or not self.hud or not node or not node.visible or node.controlEnabled == false
        or node.controlPass ~= self.controlPass then return end
    if node.controlDrag then
        if self.active then self:_released() end
        if self.suppressClick then self.suppressClick = false return end
    end
    local ok, err = invoke(self.hud, 'activateControl', node.controlAction)
    if not ok then
        self:_error('HUD control action failed: ' .. tostring(err), false)
        self:_cancelInput()
        return
    end
    self:_syncDescriptorControls(false)
end

function Adapter:_syncDescriptorControls(poll)
    local list = self:_descriptorList()
    if not list then self:_cancelInput() return false end
    if poll then
        self:_pollTouch()
        list = self:_descriptorList()
        if not list then self:_cancelInput() return false end
    end
    self.controlPass = (self.controlPass or 0) + 1
    local seen = self.controlSeen or {}
    self.controlSeen = seen
    for id in pairs(seen) do seen[id] = nil end
    local ready = #list > 0
    self.clickMoveAvailable = false
    self.dragBindingsSupported = false
    for i = 1, #list do
        local d = list[i]
        if not self:_descriptorValid(d) or seen[d.id] then
            ready = false
            if not self.descriptorWarning then
                self.descriptorWarning = true
                self:_warn('HUD controls contain invalid or duplicate descriptors')
            end
        else
            local id = d.id
            seen[id] = true
            local node = self:_button(id, 20000 + d.z, function() self:_descriptorClick(id) end)
            if node then
                node.controlPass = self.controlPass
                node.controlAction = d.action
                node.controlEnabled = d.enabled ~= false
                node.controlDrag = d.drag == true
                if node.controlDrag and not node.dragBindingsConfigured then
                    node.dragBindingsConfigured = true
                    local pressOK = self:_bind(node, 'OnPressed', function()
                        if node.controlDrag and node.controlEnabled and node.visible then self:_pressed() end
                    end, false)
                    local releaseOK = self:_bind(node, 'OnReleased', function()
                        if node.controlDrag and node.controlEnabled and node.visible then self:_released() end
                    end, false)
                    node.dragBindingsSupported = pressOK == true and releaseOK == true
                end
                if node.controlDrag and node.dragBindingsSupported then self.dragBindingsSupported = true end
                if node.controlEnabled and (d.action == 'move_left' or d.action == 'move_right'
                    or d.action == 'move_up' or d.action == 'move_down' or d.action == 'reset_position') then
                    self.clickMoveAvailable = true
                end
                self:_position(node, d.x, d.y)
                self:_size(node, d.w, d.h)
                self:_z(node, 20000 + d.z)
                self:_visible(node, true, true)
            else ready = false end
        end
    end
    for _, node in pairs(self.controls) do
        if node.controlPass ~= self.controlPass then self:_visible(node, false, true) end
    end
    if self.inputFailed then self:_cancelInput() return false end
    self.inputSupported = ready
    return ready
end

function Adapter:syncInput(hud, pc, toCanvas)
    if not self:valid() or type(hud) ~= 'table' then return false end
    if self.pc ~= pc then
        if self.active and self.hud then self.hud:pointer('cancel', 0, 0, self.active.id) end
        self.active = nil
        self.touchStates = {}
        self.touchPositions = {}
        self.touchSignature = nil
        self.dragSupported = false
        self.touchTupleAvailable = false
        self.touchTupleObserved = false
        self.touchDownObserved = false
        self.touchMovementObserved = false
        self.menuCaptureObserved = false
        self.menuMovementObserved = false
        self.touchSamples, self.menuCaptures, self.menuMoves = 0, 0, 0
    end
    self.hud, self.pc, self.toCanvas = hud, pc, toCanvas
    self:_size(self.root, hud.width, hud.height)
    if self.inputFailed then self:_cancelInput() return false end
    if not method(pc, 'GetInputTouchState') then self.dragSupported = false end
    if method(hud, 'getControls') and method(hud, 'activateControl') then
        return self:_syncDescriptorControls(true)
    end
    self.descriptors = nil
    local menu = self:_button('menu', 20000, function()
        if self.disposed or not self.hud then return end
        if self.active then self:_released() end
        if self.suppressClick then self.suppressClick = false return end
        self.hud.open = not self.hud.open
    end, function() self:_pressed() end, function() self:_released() end)
    self.dragBindingsSupported = menu ~= nil and menu.dragBindingsSupported == true
    if menu then self:_pollTouch() end
    if menu then
        self:_position(menu, hud.buttonX, hud.buttonY)
        self:_size(menu, hud.buttonW, hud.buttonH)
        self:_visible(menu, true, true)
    end
    local ready = menu ~= nil
    if hud.open then
        local blocker = self:_button('panel', 20001)
        if blocker then
            self:_position(blocker, hud.panelX, hud.panelY)
            self:_size(blocker, hud.panelW, hud.panelH)
            self:_visible(blocker, true, true)
        end
        ready = ready and blocker ~= nil
        local close = self:_button('close', 20003, function() if self.hud then self.hud.open = false end end)
        if close then
            self:_position(close, hud.panelX + hud.panelW - (hud.closeWidth or 30) * hud.panelScale, hud.panelY)
            self:_size(close, (hud.closeWidth or 30) * hud.panelScale, (hud.headerHeight or 32) * hud.panelScale)
            self:_visible(close, true, true)
        end
        ready = ready and close ~= nil
        for i = 1, #KEYS do
            local key = KEYS[i]
            local row = self:_button('row' .. i, 20002, function()
                if not self.disposed and self.hud then self.hud:setFeature(key, not self.hud.features[key]) end
            end)
            if row then
                self:_position(row, hud.panelX, hud.panelY + ((hud.headerHeight or 32) + (i - 1) * (hud.rowHeight or 26)) * hud.panelScale)
                self:_size(row, hud.panelW, (hud.rowHeight or 26) * hud.panelScale)
                self:_visible(row, true, true)
            end
            ready = ready and row ~= nil
        end
    else
        for name, node in pairs(self.controls) do if name ~= 'menu' then self:_visible(node, false, true) end end
    end
    if self.inputFailed then self:_cancelInput() return false end
    self.inputSupported = ready
    return ready
end

function Adapter:getStatus()
    return {
        ready = self:valid(), widgets = self.total, maxWidgets = self.maxWidgets,
        createdThisFrame = self.createdThisFrame, droppedCommands = self.droppedCommands,
        warming = self.deferred > 0 and self.total < self.maxWidgets,
        error = self.error, errors = self.errors, warning = self.warning, warnings = self.warnings,
        inputSupported = self.inputSupported, dragSupported = self.dragSupported,
        touchMethodAvailable = method(self.pc, 'GetInputTouchState') ~= nil,
        touchTupleAvailable = self.touchTupleAvailable == true, touchTupleObserved = self.touchTupleObserved,
        touchDownObserved = self.touchDownObserved, touchMovementObserved = self.touchMovementObserved,
        menuCaptureObserved = self.menuCaptureObserved, menuMovementObserved = self.menuMovementObserved,
        touchSamples = self.touchSamples, menuCaptures = self.menuCaptures, menuMoves = self.menuMoves,
        clickMoveAvailable = self.clickMoveAvailable == true,
        dragBindingsAvailable = self.dragBindingsSupported == true,
        textBoundsMeasured = self.textMeasured, textBoundsClipped = self.textClipped, textBoundsUnverified = self.textUnverified,
        touchInput = 'PlayerController coordinates; static tuples do not verify drag; use move controls when coordinates are unavailable',
        nativeBindingsVerified = false, captureExclusionSupported = false,
        dotRendering = 'Font glyph; device font metrics unverified'
    }
end

function Adapter:dispose()
    if self.disposed then return end
    self:_cancelInput()
    self.disposed = true
    for i = #self.owned, 1, -1 do self:_remove(self.owned[i]) end
    self.owned = {}
    self.pools = {}
    self.actorGroups = {}
    self.actorByKey = {}
    self.actorFree = {}
    self.currentGroup = nil
    self.controls = {}
    self.root = nil
    self.hud = nil
    self.pc = nil
end
return Adapter
end)()

-- ========================================================================
-- 4. OPTIONAL CAMERA AND BODY COLORS
-- ========================================================================

local ShayanVisualFeatures = (function()
local Visual = {}
Visual.__index = Visual
Visual.COLORS = {
    {name='Red',    r=50.00,g=0.10,b=0.14},
    {name='Cyan',   r=0.00,g=1.00,b=50.00},
    {name='Green',  r=0.10,g=50.00,b=0.25},
    {name='Yellow', r=50.00,g=50.00,b=0.05},
    {name='Orange', r=50.00,g=0.45,b=0.05},
    {name='Purple', r=0.62,g=0.25,b=50.00},
    {name='Pink',   r=50.00,g=0.25,b=0.65},
    {name='White',  r=50.00,g=50.00,b=50.00},
    {name='Blue',   r=0.10,g=0.35,b=50.00},
    {name='Lime',   r=0.60,g=50.00,b=0.05},
}
local MAX_ACTORS, WORK_BUDGET = 256, 2
local FOV_INTERVAL, WALL_INTERVAL, FOV_VALUE = 0.2, 0.25, 120
local function finite(v) return type(v) == 'number' and v == v and v > -math.huge and v < math.huge end
local function read(object, key)
    if object == nil then return nil end
    local ok, value = pcall(function() return object[key] end)
    if ok then return value end
end
local function invoke(object, key, ...)
    local fn = read(object, key)
    if type(fn) ~= 'function' then return false end
    local ok, value = pcall(fn, object, ...)
    return ok and value ~= false, value
end
local function static(object, key, ...)
    local fn = read(object, key)
    if type(fn) ~= 'function' then return false end
    local ok, value = pcall(fn, ...)
    return ok and value ~= false, value
end
local function loadNative(env, key, path)
    local value = read(env, key)
    if value ~= nil then return value end
    local import = read(env, 'import')
    if type(import) == 'function' then
        local ok, result = pcall(import, path)
        if ok then return result end
    end
end
local function same(a, b) return finite(a) and finite(b) and math.abs(a - b) < 0.000001 end
local function index(v, fallback)
    if finite(v) and v == math.floor(v) and v >= 1 and v <= #Visual.COLORS then return v end
    return fallback
end

function Visual.new(env)
    return setmetatable({
        env = env or _G, nextFov = 0, nextWall = 0, lastTime = nil,
        fovCamera = nil, fovOriginal = nil, ipadAvailable = nil, wallAvailable = nil,
        fovError = nil, wallError = nil, wallEnabled = false, consoleWorld = nil,
        consoleReady = false, nextConsole = 0, owned = {}, ownedOrder = {}, cursor = 1,
        visibleIndex = 1, occludedIndex = 6, revision = 1, visibleNative = nil,
        occludedNative = nil, processedLastUpdate = 0, coverage = 'body_mesh_only',
        disposed = false
    }, Visual)
end

function Visual:_valid(object)
    if object == nil then return false end
    local ok, valid = static(read(self.env, 'slua'), 'isValid', object)
    if ok and valid == true then return true end
    ok, valid = invoke(read(self.env, 'Game'), 'IsValid', object)
    return ok and valid == true
end

function Visual:_restoreFOV()
    local camera = self.fovCamera
    if camera == nil then return true end
    if not self:_valid(camera) then
        self.fovCamera, self.fovOriginal = nil, nil
        return true
    end
    local current = read(camera, 'FieldOfView')
    if finite(current) and not same(current, FOV_VALUE) then
        self.fovCamera, self.fovOriginal = nil, nil
        return true
    end
    if not same(current, FOV_VALUE) then
        self.fovError = 'iPad view: original FOV restore awaits a readable camera'
        return false
    end
    local original = self.fovOriginal
    local ok = pcall(function() camera.FieldOfView = original end)
    if ok and same(read(camera, 'FieldOfView'), original) then
        self.fovCamera, self.fovOriginal = nil, nil
        self.fovError = nil
        return true
    end
    self.fovError = 'iPad view: original FOV restore failed'
    return false
end

function Visual:_updateFOV(pawn, enabled, now)
    if not enabled then self:_restoreFOV() self.nextFov = 0 return end
    if not self:_valid(pawn) then self:_restoreFOV() return end
    local camera = read(pawn, 'ThirdPersonCameraComponent')
    if self.fovCamera ~= nil and self.fovCamera ~= camera then
        if not self:_restoreFOV() then return end
        self.nextFov = 0
    end
    if now < self.nextFov then return end
    self.nextFov = now + FOV_INTERVAL
    if not self:_valid(camera) then
        self.ipadAvailable = false
        self.fovError = 'iPad view: third-person camera unavailable'
        return
    end
    local aiming = read(pawn, 'bIsWeaponAiming')
    local inVehicle = read(pawn, 'bIsInVehicle')
    local vehicle = read(pawn, 'CurrentVehicle')
    if not self:_valid(vehicle) then
        local ok, value = invoke(pawn, 'GetVehicle')
        if ok then vehicle = value end
    end
    if aiming == true or aiming == 1 or inVehicle == true or inVehicle == 1 or self:_valid(vehicle) then
        self:_restoreFOV()
        return
    end
    local current = read(camera, 'FieldOfView')
    if not finite(current) then
        self.ipadAvailable = false
        self.fovError = 'iPad view: FieldOfView is unreadable'
        return
    end
    if same(current, FOV_VALUE) then
        self.ipadAvailable = true
        self.fovError = nil
        return
    end
    local original = self.fovCamera == camera and self.fovOriginal or current
    local ok = pcall(function() camera.FieldOfView = FOV_VALUE end)
    if ok and same(read(camera, 'FieldOfView'), FOV_VALUE) then
        self.fovCamera, self.fovOriginal = camera, original
        self.ipadAvailable = true
        self.fovError = nil
    else
        if same(read(camera, 'FieldOfView'), FOV_VALUE) then self.fovCamera, self.fovOriginal = camera, original end
        self.ipadAvailable = false
        self.fovError = 'iPad view: FieldOfView write failed'
    end
end

function Visual:_color(which)
    local c = Visual.COLORS[which]
    local ctor = loadNative(self.env, 'FLinearColor', 'LinearColor')
    if ctor ~= nil then
        local ok, value = pcall(function() return ctor(c.r, c.g, c.b, 1) end)
        if ok and value ~= nil then return value end
    end
    return { R = c.r, G = c.g, B = c.b, A = 1 }
end

function Visual:_console(now)
    local ok, world = static(read(self.env, 'slua'), 'getWorld')
    if not ok or world == nil then
        self.wallError = 'Wall color: world unavailable'
        return false
    end
    if self.consoleWorld ~= world then
        self.consoleWorld = world
        self.consoleReady = false
        self.nextConsole = 0
    end
    if self.consoleReady then return true end
    if now < self.nextConsole then return false end
    self.nextConsole = now + 1
    local ksl = loadNative(self.env, 'KismetSystemLibrary', 'KismetSystemLibrary')
    local applied = static(ksl, 'ExecuteConsoleCommand', world, 'r.EnableDrawDyeingColor 1')
    if not applied then
        self.wallAvailable = false
        self.wallError = 'Wall color: dyeing console gate unavailable'
        return false
    end
    self.consoleReady = true
    return true
end

function Visual:_removeEntry(entry)
    if self.owned[entry.actor] == entry then self.owned[entry.actor] = nil end
    for i = #self.ownedOrder, 1, -1 do
        if self.ownedOrder[i] == entry then table.remove(self.ownedOrder, i) break end
    end
end

function Visual:_disable(entry)
    if not entry then return true end
    if not self:_valid(entry.mesh) then self:_removeEntry(entry) return true end
    if invoke(entry.mesh, 'SetDrawDyeing', false) then
        self:_removeEntry(entry)
        return true
    end
    entry.applied = false
    self.wallError = 'Wall color: owned body-mesh cleanup failed'
    return false
end

function Visual:_clearWall()
    for i = #self.ownedOrder, 1, -1 do self:_disable(self.ownedOrder[i]) end
    self.cursor = 1
end

function Visual:_applyActor(actor)
    if not self:_valid(actor) then
        if self.owned[actor] then self:_disable(self.owned[actor]) end
        return
    end
    local mesh = read(actor, 'Mesh')
    local entry = self.owned[actor]
    if entry and entry.mesh ~= mesh then
        if not self:_disable(entry) then return end
        entry = nil
    end
    if not self:_valid(mesh) then return end
    if entry and entry.applied and entry.revision == self.revision then return end
    for _, method in ipairs({ 'SetDrawDyeing', 'SetDrawDyeingMode', 'SetVisibleDyeingColor', 'SetOccludedDyeingColor' }) do
        if type(read(mesh, method)) ~= 'function' then
            if entry then entry.applied = false end
            self.wallAvailable = false
            self.wallError = 'Wall color: body mesh lacks ' .. method
            return
        end
    end
    if entry then entry.applied = false end
    local success = invoke(mesh, 'SetDrawDyeingMode', 1)
        and invoke(mesh, 'SetVisibleDyeingColor', self.visibleNative)
        and invoke(mesh, 'SetOccludedDyeingColor', self.occludedNative)
    if not success then
        self.wallAvailable = false
        self.wallError = 'Wall color: body-mesh color application failed'
        return
    end
    if not entry then
        entry = { actor = actor, mesh = mesh, applied = false, revision = 0 }
        self.owned[actor] = entry
        self.ownedOrder[#self.ownedOrder + 1] = entry
    end
    if not invoke(mesh, 'SetDrawDyeing', true) then
        self.wallAvailable = false
        self.wallError = 'Wall color: body-mesh enable failed'
        self:_disable(entry)
        return
    end
    entry.applied = true
    entry.revision = self.revision
    self.wallAvailable = true
    self.wallError = nil
end

function Visual:_updateWall(pawn, snapshots, enabled, settings, now)
    if not enabled then
        if self.wallEnabled or #self.ownedOrder > 0 then self:_clearWall() end
        self.wallEnabled = false
        self.nextWall = 0
        return
    end
    local vi, oi = index(settings.visibleColor, 1), index(settings.occludedColor, 6)
    if vi ~= self.visibleIndex or oi ~= self.occludedIndex or self.visibleNative == nil then
        self.visibleIndex, self.occludedIndex = vi, oi
        self.visibleNative, self.occludedNative = self:_color(vi), self:_color(oi)
        self.revision = self.revision + 1
    end
    if not self.wallEnabled then self.nextWall = 0 self.cursor = 1 end
    self.wallEnabled = true
    if now < self.nextWall then return end
    self.nextWall = now + WALL_INTERVAL
    local current, actors = {}, {}
    if type(snapshots) == 'table' then
        for i = 1, math.min(#snapshots, MAX_ACTORS) do
            local actor = read(snapshots[i], 'actor')
            if actor ~= nil and actor ~= pawn and not current[actor] then
                current[actor] = true
                actors[#actors + 1] = actor
            end
        end
    end
    local budget = WORK_BUDGET
    for i = #self.ownedOrder, 1, -1 do
        local entry = self.ownedOrder[i]
        if not current[entry.actor] then
            self:_disable(entry)
            budget = budget - 1
            self.processedLastUpdate = self.processedLastUpdate + 1
            if budget == 0 then break end
        end
    end
    if budget == 0 or #actors == 0 then return end
    if not self:_console(now) then return end
    local count = math.min(budget, #actors)
    for _ = 1, count do
        if self.cursor > #actors then self.cursor = 1 end
        local actor = actors[self.cursor]
        self.cursor = self.cursor + 1
        self.processedLastUpdate = self.processedLastUpdate + 1
        if self.owned[actor] or #self.ownedOrder < MAX_ACTORS then self:_applyActor(actor) end
    end
end

function Visual:update(pawn, snapshots, settings, now)
    if self.disposed then return end
    settings = type(settings) == 'table' and settings or {}
    self.processedLastUpdate = 0
    local ipad = settings.ipadView == true
    local wall = settings.wallHack == true
    if not finite(now) or now < 0 then
        if not ipad then self:_restoreFOV() end
        if not wall then self:_clearWall() self.wallEnabled = false end
        return
    end
    if self.lastTime ~= nil and now < self.lastTime then
        self.nextFov, self.nextWall, self.nextConsole = 0, 0, 0
    end
    self.lastTime = now
    self:_updateFOV(pawn, ipad, now)
    self:_updateWall(pawn, snapshots, wall, settings, now)
end

function Visual:dispose()
    self:_restoreFOV()
    self:_clearWall()
    self.wallEnabled = false
    self.disposed = true
end

function Visual:getStatus()
    local applied = 0
    for _, entry in ipairs(self.ownedOrder) do
        if entry.applied and entry.revision == self.revision then applied = applied + 1 end
    end
    return {
        ipadAvailable = self.ipadAvailable, wallAvailable = self.wallAvailable,
        appliedActors = applied, ownedMeshes = #self.ownedOrder,
        lastError = self.wallError or self.fovError, wallCoverage = self.coverage,
        wallStateRestoration = 'owned_dye_flag_off_only',
        processedLastUpdate = self.processedLastUpdate, maxActors = MAX_ACTORS,
        actorsPerUpdate = WORK_BUDGET, wallInterval = WALL_INTERVAL,
        ipadFov = FOV_VALUE, ipadInterval = FOV_INTERVAL,
        pendingFovRestore = self.fovCamera ~= nil and self.disposed,
        pendingWallCleanup = self.disposed and #self.ownedOrder > 0
    }
end

return Visual
end)()

-- ========================================================================
-- 5. OPTIONAL SOURCE-BACKED AIM
-- ========================================================================

local ShayanAimFeatures = (function()
local Aim = {}
Aim.__index = Aim
local sqrt, abs, min, max = math.sqrt, math.abs, math.min, math.max
local function finite(value) return type(value) == 'number' and value == value and value > -math.huge and value < math.huge end
local function indexed(object, key) return object[key] end
local function read(object, key)
    if object == nil then return nil end
    local ok, value = pcall(indexed, object, key)
    if ok then return value end
end
local function call(object, key, ...)
    local fn = read(object, key)
    if type(fn) ~= 'function' then return nil end
    local ok, value = pcall(fn, object, ...)
    if ok then return value end
end
local function static(object, key, ...)
    local fn = read(object, key)
    if type(fn) ~= 'function' then return nil end
    local ok, value = pcall(fn, ...)
    if ok then return value end
end
local function vector(value)
    if finite(read(value, 'X')) and finite(read(value, 'Y')) and finite(read(value, 'Z')) then return value end
end
local function nonzero(value)
    value = vector(value)
    if value and (value.X ~= 0 or value.Y ~= 0 or value.Z ~= 0) then return value end
end
local function import(env, name)
    if env[name] ~= nil then return env[name] end
    if type(env.import) == 'function' then
        local ok, value = pcall(env.import, name)
        if ok then return value end
    end
end
local function wrap(degrees) return (degrees + 180) % 360 - 180 end

function Aim.new(env)
    env = env or _G
    return setmetatable({
        env = env, mathLibrary = import(env, 'KismetMathLibrary'),
        gameplayStatics = env.UGameplayStatics or import(env, 'GameplayStatics'),
        cursor = 1, members = {}, zero = { X = 0, Y = 0, Z = 0 }, candidateBudget = 8, maxSnapshots = 256,
        snapshotMaxAge = .3, lastStatus = 'inactive', processedLastUpdate = 0,
        rotationCalls = 0, assistantAvailable = nil, mortarAvailable = nil, sniperAvailable = nil
    }, Aim)
end

function Aim:_valid(value)
    if value == nil then return false end
    if static(self.env.slua, 'isValid', value) == true then return true end
    return call(self.env.Game, 'IsValid', value) == true
end

function Aim:_clear(reason)
    self.pc, self.pawn, self.weapon, self.world, self.activeMode = nil, nil, nil, nil, nil
    self.target, self.targetRow, self.lastTime = nil, nil, nil
    self.cursor = 1
    for actor in pairs(self.members) do self.members[actor] = nil end
    self.lastStatus = reason or 'inactive'
    return false
end

function Aim:_fail(reason)
    self.target, self.targetRow = nil, nil
    self.lastStatus = reason
    return false
end

function Aim:_weapon(pawn)
    local observed = false
    local getter = read(pawn, 'GetCurrentWeapon')
    if type(getter) == 'function' then
        local ok, current = pcall(getter, pawn)
        if ok then
            observed = true
            if self:_valid(current) then return current end
        end
    end
    local manager = read(pawn, 'WeaponManagerComponent')
    if self:_valid(manager) then
        local current = read(manager, 'CurrentWeapon')
        if current ~= nil then observed = true end
        if self:_valid(current) then return current end
    end
    getter = read(pawn, 'GetCurrentShootWeapon')
    if type(getter) == 'function' then
        local ok, current = pcall(getter, pawn)
        if ok then
            observed = true
            if self:_valid(current) then return current end
        end
    end
    if observed then return nil end
    local replicated = read(manager, 'CurrentWeaponReplicated')
    if self:_valid(replicated) then return replicated end
end

-- Weapon classification is deliberately tolerant: many builds return an asset/class
-- path (e.g. BP_ShootWeapon_M24_C) rather than the short display name.
local SNIPER_NAMES = {
    'kar98', 'kar98k', 'm24', 'awm', 'amr', 'mosin', 'win94',
    'sks', 'slr', 'mini14', 'mini_14', 'mk14', 'qbu', 'mk12', 'vss'
}
local SNIPER_IDS = {
    [103001] = true, [103002] = true, [103003] = true, [103004] = true,
    [103006] = true, [103009] = true, [103012] = true
}
function Aim:_weaponKind(weapon)
    if not self:_valid(weapon) then return 'unknown' end

    local id = call(weapon, 'GetWeaponID') or read(weapon, 'WeaponID') or read(weapon, 'ID')
    if type(id) == 'number' and SNIPER_IDS[id] then return 'sniper' end

    local name = call(weapon, 'GetWeaponName')
    if type(name) ~= 'string' then
        name = read(weapon, 'WeaponName') or read(weapon, 'Name') or ''
    end
    if type(name) ~= 'string' or not name:find('%S') then
        return 'unknown'
    end

    local lower = name:lower():gsub('[%s_%-]', '')
    if lower:find('mortar', 1, true) or lower:find('cối', 1, true) then
        return 'mortar'
    end

    -- Substring matching handles display names, Blueprint names and asset paths.
    for i = 1, #SNIPER_NAMES do
        if lower:find(SNIPER_NAMES[i]:gsub('[%s_%-]', ''), 1, true) then
            return 'sniper'
        end
    end
    return 'other'
end

local function modeAllowed(settings, kind, mode)
    if settings[mode] ~= true then return false end
    if mode == 'mortar' then return kind == 'mortar' end
    if mode == 'sniper' then return kind == 'sniper' end
    if mode == 'force' then return kind ~= 'mortar' end
    return kind == 'other' or (kind == 'sniper' and settings.sniper ~= true)
end

function Aim:_team(actor)
    local team = call(actor, 'GetTeamID') or read(actor, 'TeamID')
    if team ~= nil then return team end
    local state = call(actor, 'GetPlayerStateSafety') or call(actor, 'GetPlayerState') or read(actor, 'PlayerState')
    if self:_valid(state) then return call(state, 'GetTeamID') or read(state, 'TeamID') end
end

function Aim:_alive(actor)
    if not self:_valid(actor) or read(actor, 'bHidden') == true or read(actor, 'bIsDead') == true
        or read(actor, 'bIsDeadFlag') == true or read(read(actor, 'Mesh'), 'bHidden') == true then return false end
    if call(actor, 'IsDead') == true or call(actor, 'IsAlive') == false then return false end
    local health = call(actor, 'GetHealth')
    if health == nil then health = read(actor, 'Health') end
    if health == nil then health = read(actor, 'HP') end
    if health ~= nil then return finite(health) and health > 0 end
    return call(actor, 'IsAlive') == true or call(actor, 'IsDead') == false
end

function Aim:_isBot(actor)
    if read(actor, 'bIsAI') == true or read(actor, 'IsAI') == true or read(actor, 'bIsAIActor') == true then return true end
    local fn = read(actor, 'IsAICharacter')
    if type(fn) == 'function' then
        local ok, result = pcall(fn, actor)
        if ok and result == true then return true end
    end
    fn = read(actor, 'IsBot')
    if type(fn) == 'function' then
        local ok, result = pcall(fn, actor)
        if ok and result == true then return true end
    end
    local state = call(actor, 'GetPlayerStateSafety') or call(actor, 'GetPlayerState') or read(actor, 'PlayerState')
    if self:_valid(state) then
        if read(state, 'bIsBot') == true or read(state, 'bIsAI') == true or read(state, 'bIsABot') == true then return true end
        fn = read(state, 'IsABot')
        if type(fn) == 'function' then
            local ok, result = pcall(fn, state)
            if ok and result == true then return true end
        end
    end
    return false
end

function Aim:_visible(pc, actor)
    if not pc or not actor then return true end
    local fn = read(pc, 'LineOfSightTo')
    if type(fn) ~= 'function' then return true end
    local ok, result = pcall(fn, pc, actor)
    return not ok or result == true
end

function Aim:_candidate(actor, row, pawn, now, settings, pc)
    if type(row) ~= 'table' or row.actor ~= actor or actor == pawn or not self:_alive(actor) then return false end
    if row.alive ~= true or not finite(row.health) or row.health <= 0 then return false end
    if row.updatedAt ~= nil and (not finite(row.updatedAt) or now - row.updatedAt < 0 or now - row.updatedAt > self.snapshotMaxAge) then return false end
    if settings and settings.ignoreKnocked == true and (row.knocked == true or read(actor, 'HealthStatus') == 1) then return false end
    if settings and settings.ignoreBots == true and self:_isBot(actor) then return false end
    if settings and settings.visibility == true and not self:_visible(pc, actor) then return false end
    local mine, theirs = self:_team(pawn), self:_team(actor)
    return mine ~= nil and theirs ~= nil and tostring(mine) ~= tostring(theirs)
end

function Aim:_position(actor, mode)
    if mode == 'force' or mode == 'sniper' then
        local mesh = read(actor, 'Mesh')
        if self:_valid(mesh) then
            -- UE builds differ in socket casing/name. Try the common variants before
            -- falling back to the character bone API.
            local sockets = { 'head', 'Head', 'HEAD', 'head_socket', 'HeadSocket' }
            for i = 1, #sockets do
                local point = nonzero(call(mesh, 'GetSocketLocation', sockets[i]))
                if point then return point end
            end
        end
        return nonzero(call(actor, 'GetBonePos', 'head', self.zero))
            or nonzero(call(actor, 'GetBonePos', 'Head', self.zero))
            or nonzero(call(actor, 'GetSocketLocation', 'head'))
            or nonzero(call(actor, 'GetSocketLocation', 'Head'))
    end
    local point = nonzero(call(actor, 'GetBonePos', 'pelvis', self.zero))
        or nonzero(call(actor, 'GetSocketLocation', 'pelvis'))
    if point then return point end
    if mode == 'mortar' then return vector(call(actor, 'K2_GetActorLocation') or call(actor, 'GetActorLocation')) end
end

function Aim:_score(point, context)
    if not point or type(context.project) ~= 'function' then return nil end
    local ok, x, y, reuse = pcall(context.project, point, self.projected)
    if ok then self.projected = reuse or self.projected end
    if not ok or not finite(x) or not finite(y) or x < 0 or y < 0 or x > context.width or y > context.height then return nil end
    local dx, dy = (x - context.centerX) / context.radius, (y - context.centerY) / context.radius
    local score = dx * dx + dy * dy
    if finite(score) and score <= 1 then return score end
end

function Aim:_geometry(context, now)
    if type(context) ~= 'table' or context.world == nil or not finite(context.snapshotTime)
        or now - context.snapshotTime < 0 or now - context.snapshotTime > self.snapshotMaxAge then return false end
    return finite(context.width) and context.width > 0 and finite(context.height) and context.height > 0
        and finite(context.centerX) and finite(context.centerY) and finite(context.radius) and context.radius > 0
        and type(context.project) == 'function' and type(context.isCurrent) == 'function'
end

function Aim:_current(pc, pawn, weapon, context, mode, settings)
    local ok, current = pcall(context.isCurrent, pc, pawn)
    if not ok or current ~= true or not self:_valid(pc) or not self:_alive(pawn) then return false end
    local world
    if type(context.getWorld) == 'function' then
        local worldOK, value = pcall(context.getWorld)
        if worldOK then world = value end
    else
        world = static(self.env.slua, 'getWorld')
    end
    if world ~= context.world or self:_weapon(pawn) ~= weapon then return false end
    local kind = self:_weaponKind(weapon)
    if not modeAllowed(settings, kind, mode) then return false end
    if mode == 'mortar' then return kind == 'mortar' and read(weapon, 'MortarState') == 2 end
    return (mode == 'force' or read(pawn, 'bIsWeaponAiming') == true) and self:_valid(read(weapon, 'ShootWeaponEntityComp'))
end

function Aim:_select(pawn, snapshots, context, now, mode, pc, settings)
    local total = min(#snapshots, self.maxSnapshots)
    for actor in pairs(self.members) do self.members[actor] = nil end
    for i = 1, total do
        local row = snapshots[i]
        if type(row) == 'table' and row.actor ~= nil then self.members[row.actor] = row end
    end
    local best, bestRow, bestScore = nil, nil, math.huge
    local row = self.target and self.members[self.target]
    if row and self:_candidate(self.target, row, pawn, now, settings, pc) then
        local score = self:_score(self:_position(self.target, mode), context)
        if score then best, bestRow, bestScore = self.target, row, score end
    end
    if mode == 'mortar' and best then return best, bestRow end
    if total == 0 then return nil end
    if self.cursor > total then self.cursor = 1 end
    for _ = 1, min(total, self.candidateBudget) do
        local candidate = snapshots[self.cursor]
        self.cursor = self.cursor % total + 1
        self.processedLastUpdate = self.processedLastUpdate + 1
        local actor = type(candidate) == 'table' and candidate.actor
        if actor and actor ~= best and self:_candidate(actor, candidate, pawn, now, settings, pc) then
            local score = self:_score(self:_position(actor, mode), context)
            if score and score < bestScore then best, bestRow, bestScore = actor, candidate, score end
        end
    end
    return best, bestRow
end

function Aim:_camera(pc)
    local camera = call(pc, 'GetPlayerCameraManager') or read(pc, 'PlayerCameraManager')
    if not self:_valid(camera) then camera = static(self.gameplayStatics, 'GetPlayerCameraManager', pc, 0) end
    if self:_valid(camera) then return vector(call(camera, 'GetCameraLocation')) end
end

local function trajectory(launch, speed, gravity, target)
    local dx = max(500, sqrt((target.X - launch.X) ^ 2 + (target.Y - launch.Y) ^ 2) - 80)
    local dy = target.Z - launch.Z
    local required = gravity * (dy + sqrt(dx * dx + dy * dy))
    if speed * speed < required then speed = sqrt(required) + 100 end
    local v2 = speed * speed
    local discriminant = v2 * v2 - gravity * (gravity * dx * dx + 2 * dy * v2)
    if discriminant >= 0 then
        local radians = math.atan((v2 + sqrt(discriminant)) / (gravity * dx))
        local degrees = math.deg(radians)
        if finite(degrees) and degrees >= 35 and degrees <= 89.5 then
            return true, degrees, dx / (speed * math.cos(radians)), dx
        end
    end
    return false, 45, 0, dx
end
local function solve(launch, target)
    local a, b, c, d = trajectory(launch, 9070, 980 * 2.8, target)
    local e, f, g, h = trajectory(launch, 12520, 980 * 4.0, target)
    local i, j, k, l = trajectory(launch, 16800, 980 * 4.5, target)
    if a and d <= 25000 then return a, b, c, d end
    if e and h <= 40000 then return e, f, g, h end
    if i then return i, j, k, l end
    if a then return a, b, c, d end
    return false, 45, 0, d or h or l or 0
end
local function predict(actor, base, launch)
    local velocity = call(actor, 'GetVelocity')
    local vx, vy = read(velocity, 'X'), read(velocity, 'Y')
    if not finite(vx) or not finite(vy) or abs(vx) + abs(vy) < .01 then return base, nil end
    local predicted = { X = base.X, Y = base.Y, Z = base.Z }
    local previous
    for _ = 1, 2 do
        local ok, angle, flight, distance = solve(launch, predicted)
        if not ok then break end
        previous = { ok, angle, flight, distance }
        if not finite(flight) or flight <= 0 or flight > 15 then break end
        predicted.X, predicted.Y = base.X + vx * flight, base.Y + vy * flight
    end
    return predicted, previous
end

function Aim:_rotation(pc, pawn, target, point, mode, delta)
    local current = call(pc, 'GetControlRotation')
    local pitch, yaw, roll = read(current, 'Pitch'), read(current, 'Yaw'), read(current, 'Roll')
    if not finite(pitch) or not finite(yaw) then return nil, 'rotation_unavailable' end
    if not finite(roll) then roll = 0 end
    if mode == 'assistant' or mode == 'sniper' or mode == 'force' then
        local camera = self:_camera(pc)
        if not camera then return nil, 'camera_unavailable' end
        local desired = static(self.mathLibrary, 'FindLookAtRotation', camera, point)
        local desiredPitch, desiredYaw = read(desired, 'Pitch'), read(desired, 'Yaw')
        if not finite(desiredPitch) or not finite(desiredYaw) then return nil, 'look_at_unavailable' end
        local dp, dy = wrap(desiredPitch - pitch), wrap(desiredYaw - yaw)
        local distance = sqrt(dp * dp + dy * dy)
        local maximum = (mode == 'sniper' and 45 or (mode == 'force' and 120 or 90)) * min(delta, .05)
        local fraction = distance > maximum and maximum / distance or 1
        local ok = pcall(function()
            desired.Pitch = pitch + dp * fraction
            desired.Yaw = yaw + dy * fraction
            desired.Roll = roll
        end)
        if not ok then return nil, 'rotation_unavailable' end
        return desired
    end
    local location = vector(call(pawn, 'K2_GetActorLocation') or call(pawn, 'GetActorLocation'))
    if not location then return nil, 'launch_position_unavailable' end
    local launch = { X = location.X, Y = location.Y, Z = location.Z + 50 }
    local predicted, previous = predict(target, point, launch)
    local ok, angle = solve(launch, predicted)
    if not ok and previous then ok, angle = previous[1], previous[2] end
    if not ok then return nil, 'trajectory_unavailable' end
    local desired = static(self.mathLibrary, 'FindLookAtRotation', self:_camera(pc) or launch, predicted)
    local desiredYaw = read(desired, 'Yaw')
    if not finite(desiredYaw) then return nil, 'look_at_unavailable' end
    local desiredPitch = ((angle - 45) / 43) * 90 - 60
    local final = { Pitch = pitch + wrap(desiredPitch - pitch), Yaw = yaw + wrap(desiredYaw - yaw), Roll = 0 }
    if not finite(final.Pitch) or not finite(final.Yaw) then return nil, 'trajectory_unavailable' end
    return final
end

function Aim:update(pc, pawn, snapshots, settings, now, context)
    self.processedLastUpdate = 0
    settings = settings or {}
    if settings.assistant ~= true and settings.mortar ~= true and settings.sniper ~= true then return self:_clear('inactive') end
    if not finite(now) or not self:_geometry(context, now) then return self:_clear('context_unavailable') end
    if type(snapshots) ~= 'table' or not self:_valid(pc) or not self:_alive(pawn) then return self:_clear('player_or_targets_unavailable') end
    local weapon = self:_weapon(pawn)
    if not self:_valid(weapon) then return self:_clear('weapon_unavailable') end
    local kind = self:_weaponKind(weapon)
    if kind == 'unknown' then return self:_clear('weapon_identity_unavailable') end
    local mode
    if kind == 'mortar' then
        if settings.mortar ~= true then return self:_clear('mortar_disabled') end
        if read(weapon, 'MortarState') ~= 2 then return self:_clear('mortar_not_placed') end
        mode = 'mortar'
    else
        if kind == 'sniper' and settings.sniper == true then
            mode = 'sniper'
        elseif settings.force == true then
            mode = 'force'
        elseif settings.assistant == true then
            mode = 'assistant'
        else
            return self:_clear('assistant_disabled')
        end
        if mode ~= 'force' and read(pawn, 'bIsWeaponAiming') ~= true then return self:_clear('idle_ADS') end
        if not self:_valid(read(weapon, 'ShootWeaponEntityComp')) then return self:_clear('shoot_component_unavailable') end
    end
    if not self:_current(pc, pawn, weapon, context, mode, settings) then return self:_clear('context_changed') end
    local changed = self.pc ~= pc or self.pawn ~= pawn or self.weapon ~= weapon or self.world ~= context.world or self.activeMode ~= mode
    if changed then
        self:_clear('context_changed')
        self.pc, self.pawn, self.weapon, self.world, self.activeMode = pc, pawn, weapon, context.world, mode
    end
    local delta = self.lastTime and now - self.lastTime or 0
    if delta < 0 or delta > self.snapshotMaxAge then
        self:_clear('clock_changed')
        self.pc, self.pawn, self.weapon, self.world, self.activeMode = pc, pawn, weapon, context.world, mode
        delta = 0
    end
    self.lastTime = now
    if mode ~= 'mortar' and delta <= 0 then
        if mode == 'force' then delta = 0.016 else return self:_fail('priming_delta') end
    end
    local width, height, centerX, centerY, radius = context.width, context.height, context.centerX, context.centerY, context.radius
    local target, row = self:_select(pawn, snapshots, context, now, mode, pc, settings)
    if not target then return self:_fail('no_target_in_circle') end
    local point = self:_position(target, mode)
    if not point then return self:_fail('target_position_unavailable') end
    local rotation, reason = self:_rotation(pc, pawn, target, point, mode, delta)
    if not rotation then return self:_fail(reason) end
    if settings[mode] ~= true
        or not self:_geometry(context, now) or not self:_current(pc, pawn, weapon, context, mode, settings)
        or not self:_candidate(target, row, pawn, now, settings, pc) then return self:_fail('context_changed') end
    if context.width ~= width or context.height ~= height or context.centerX ~= centerX
        or context.centerY ~= centerY or context.radius ~= radius then return self:_fail('circle_geometry_changed') end
    local finalPoint = self:_position(target, mode)
    if not self:_score(finalPoint, context) then return self:_fail('target_left_circle') end
    local retained = false
    for i = 1, min(#snapshots, self.maxSnapshots) do
        if snapshots[i] == row and row.actor == target then retained = true break end
    end
    if not retained or settings[mode] ~= true
        or not self:_geometry(context, now) or not self:_current(pc, pawn, weapon, context, mode, settings)
        or not self:_candidate(target, row, pawn, now, settings, pc) then return self:_fail('context_changed') end
    if context.width ~= width or context.height ~= height or context.centerX ~= centerX
        or context.centerY ~= centerY or context.radius ~= radius then return self:_fail('circle_geometry_changed') end
    local fn = read(pc, 'SetControlRotation')
    if type(fn) ~= 'function' then return self:_fail('rotation_unavailable') end
    local ok, accepted = pcall(fn, pc, rotation, mode == 'mortar' and 'MortarAim' or 'CircleAim')
    if not ok or accepted == false then
        self[mode .. 'Available'] = false
        return self:_fail('rotation_rejected')
    end
    self.target, self.targetRow = target, row
    self.rotationCalls = self.rotationCalls + 1
    self.lastStatus = 'rotation_call_accepted'
    self[mode .. 'Available'] = true
    return true
end

function Aim:dispose()
    self:_clear('disposed')
    self.projected = nil
end

function Aim:getStatus()
    return {
        activeMode = self.activeMode, target = self.target, lastStatus = self.lastStatus,
        assistantSupported = true, forceSupported = true, mortarSupported = true,
        touchSimulationSupported = false, sniperSupported = true, throwableSupported = false,
        assistantAvailable = self.assistantAvailable, forceAvailable = self.forceAvailable,
        mortarAvailable = self.mortarAvailable, sniperAvailable = self.sniperAvailable,
        processedLastUpdate = self.processedLastUpdate,
        candidateBudget = self.candidateBudget, rotationCalls = self.rotationCalls,
        mortarPhysicsVerified = false, sniperBallisticCompensation = false, nativeGameVerified = false
    }
end
return Aim
end)()

-- ========================================================================
-- 6. OPTIONAL SMALL CROSSHAIR WEAPON VALUES
-- ========================================================================

local ShayanWeaponFeatures = (function()
local Weapon = {}
Weapon.__index = Weapon
local FIELDS = { 'RecoilKickADS', 'GameDeviationFactor', 'GameDeviationAccuracy' }
local VALUE, INTERVAL = .01, .2
local FIREARMS = {
    m416 = true, akm = true, ['scar-l'] = true, m762 = true, aug = true, groza = true,
    qbz = true, mk47 = true, g36c = true, ['honey badger'] = true, famas = true, ['asm abakan'] = true,
    ace32 = true, uzi = true, ump45 = true, vector = true, thompson = true, ['thompson smg'] = true,
    bizon = true, ['pp-19 bizon'] = true, ['pp-19'] = true, mp5k = true, p90 = true,
    kar98 = true, kar98k = true, m24 = true, awm = true, sks = true, vss = true, slr = true, mini14 = true,
    mk14 = true, amr = true, mk12 = true, dsr = true, ['m1 garand'] = true, s686 = true, s1897 = true,
    s12k = true, dbs = true, ns2000 = true, m249 = true, dp28 = true, ['dp-28'] = true, mg3 = true
}
local function finite(value) return type(value) == 'number' and value == value and value > -math.huge and value < math.huge end
local function same(a, b) return finite(a) and finite(b) and math.abs(a - b) < .000001 end
local function read(object, key)
    if object == nil then return nil end
    local ok, value = pcall(function() return object[key] end)
    if ok then return value end
end
local function call(object, key, ...)
    local fn = read(object, key)
    if type(fn) ~= 'function' then return nil end
    local ok, value = pcall(fn, object, ...)
    if ok then return value end
end

function Weapon.new(env)
    return setmetatable({
        env = env or _G, enabled = false, active = false, disposed = false,
        nextCheck = 0, lastTime = nil, pawn = nil, weapon = nil, entry = nil, blockedEntity = nil,
        restoring = false, smallCrosshairAvailable = nil, lastStatus = 'inactive'
    }, Weapon)
end

function Weapon:_valid(object)
    if object == nil then return false end
    local fn = read(read(self.env, 'slua'), 'isValid')
    if type(fn) == 'function' then
        local ok, valid = pcall(fn, object)
        if ok and valid == true then return true end
    end
    return call(read(self.env, 'Game'), 'IsValid', object) == true
end

function Weapon:_currentWeapon(pawn)
    local observed = false
    for _, key in ipairs({ 'GetCurrentWeapon', 'GetCurrentShootWeapon' }) do
        local fn = read(pawn, key)
        if type(fn) == 'function' then
            local ok, current = pcall(fn, pawn)
            if ok then
                observed = true
                if self:_valid(current) then return current end
            end
        end
    end
    local manager = read(pawn, 'WeaponManagerComponent')
    if self:_valid(manager) then
        local current = read(manager, 'CurrentWeapon')
        if current ~= nil then observed = true end
        if self:_valid(current) then return current end
        if not observed then
            local replicated = read(manager, 'CurrentWeaponReplicated')
            if self:_valid(replicated) then return replicated end
        end
    end
end

function Weapon:_firearm(weapon)
    local name = call(weapon, 'GetWeaponName')
    if type(name) ~= 'string' then return false end
    return FIREARMS[name:lower():match('^%s*(.-)%s*$')] == true
end

function Weapon:_ownedCount()
    local count = 0
    if self.entry then
        for i = 1, 3 do if self.entry.owned[FIELDS[i]] then count = count + 1 end end
    end
    return count
end

function Weapon:_restore()
    local entry = self.entry
    self.active = false
    if not entry then self.restoring = false return true end
    if not self:_valid(entry.entity) then self.entry = nil self.restoring = false return true end
    for i = 1, 3 do
        local key = FIELDS[i]
        if entry.owned[key] then
            local value = read(entry.entity, key)
            if same(value, VALUE) then
                pcall(function() entry.entity[key] = entry.original[key] end)
                if same(read(entry.entity, key), entry.original[key]) then entry.owned[key] = nil end
            elseif finite(value) then
                entry.owned[key] = nil
            end
        end
    end
    if self:_ownedCount() == 0 then self.entry = nil self.restoring = false return true end
    self.restoring = true
    return false
end

function Weapon:_stop(reason)
    local restored = self:_restore()
    self.lastStatus = restored and reason or 'restore_pending'
    return false
end

function Weapon:_block(entity, reason)
    self.blockedEntity, self.blockedReason = entity, reason
    self.smallCrosshairAvailable = false
    return self:_stop(reason)
end

function Weapon:_isCurrent(pawn, weapon, entity, settings)
    return settings.smallCrosshair == true and self:_valid(pawn) and self:_valid(weapon)
        and self:_valid(entity) and self:_currentWeapon(pawn) == weapon
        and read(weapon, 'ShootWeaponEntityComp') == entity and self:_firearm(weapon)
end

function Weapon:_apply(pawn, weapon, entity, settings)
    local entry = { entity = entity, original = {}, owned = {} }
    for i = 1, 3 do
        local key = FIELDS[i]
        local value = read(entity, key)
        if not finite(value) then
            self.smallCrosshairAvailable = false
            self.lastStatus = 'source_field_unavailable'
            return false
        end
        entry.original[key] = value
    end
    self.entry = entry
    for i = 1, 3 do
        local key = FIELDS[i]
        if not self:_isCurrent(pawn, weapon, entity, settings) then
            self.smallCrosshairAvailable = false
            return self:_stop('context_changed')
        end
        if not same(read(entity, key), entry.original[key]) then
            return self:_block(entity, 'external_value_changed')
        end
        if not same(entry.original[key], VALUE) then
            entry.owned[key] = true
            local ok = pcall(function() entity[key] = VALUE end)
            if not ok or not same(read(entity, key), VALUE) then
                return self:_block(entity, 'source_write_failed')
            end
        end
    end
    for i = 1, 3 do
        if not same(read(entity, FIELDS[i]), VALUE) then
            return self:_block(entity, 'external_value_changed')
        end
    end
    if not self:_isCurrent(pawn, weapon, entity, settings) then
        self.smallCrosshairAvailable = false
        return self:_stop('context_changed')
    end
    self.active = true
    self.smallCrosshairAvailable = true
    self.lastStatus = 'source_values_verified'
    return true
end

function Weapon:update(pawn, settings, now)
    if self.disposed then return false end
    settings = type(settings) == 'table' and settings or {}
    if settings.smallCrosshair ~= true then
        self.enabled = false
        self.blockedEntity = nil
        self.lastTime = nil
        self.nextCheck = 0
        self.pawn, self.weapon = nil, nil
        return self:_stop('inactive')
    end
    if not finite(now) or now < 0 then
        self.lastTime = nil
        self.nextCheck = 0
        self.weapon = nil
        return self:_stop('clock_unavailable')
    end
    if self.lastTime and now < self.lastTime then
        self.lastTime = now
        self.nextCheck = 0
        self.weapon = nil
        self.blockedEntity = nil
        return self:_stop('clock_changed')
    end
    self.lastTime = now
    if pawn ~= self.pawn then
        self.pawn = pawn
        self.weapon = nil
        self.blockedEntity = nil
        self.nextCheck = 0
        if not self:_restore() then
            self.nextCheck = now + INTERVAL
            self.lastStatus = 'restore_pending'
            return false
        end
    end
    if self.enabled and now < self.nextCheck then return self.active end
    self.enabled = true
    self.nextCheck = now + INTERVAL
    if not self:_valid(pawn) then self.weapon = nil return self:_stop('player_unavailable') end
    local weapon = self:_currentWeapon(pawn)
    if not self:_valid(weapon) or not self:_firearm(weapon) then
        self.weapon = nil
        self.smallCrosshairAvailable = false
        return self:_stop('firearm_unavailable')
    end
    local entity = read(weapon, 'ShootWeaponEntityComp')
    if not self:_valid(entity) then
        self.weapon = nil
        self.smallCrosshairAvailable = false
        return self:_stop('shoot_entity_unavailable')
    end
    if weapon ~= self.weapon then self.blockedEntity = nil end
    if self.restoring or (self.entry and self.entry.entity ~= entity) then
        if not self:_restore() then self.lastStatus = 'restore_pending' return false end
    end
    self.weapon = weapon
    if self.blockedEntity == entity then
        self.active = false
        self.lastStatus = self.blockedReason
        return false
    end
    if self.entry then
        for i = 1, 3 do
            local value = read(entity, FIELDS[i])
            if not same(value, VALUE) then
                return self:_block(entity, finite(value) and 'external_value_changed' or 'source_field_unavailable')
            end
        end
        self.active = true
        self.smallCrosshairAvailable = true
        self.lastStatus = 'source_values_verified'
        return true
    end
    return self:_apply(pawn, weapon, entity, settings)
end

function Weapon:dispose()
    self.disposed = true
    self.enabled = false
    self.blockedEntity = nil
    self.pawn, self.weapon, self.lastTime = nil, nil, nil
    return self:_stop('disposed')
end

function Weapon:getStatus()
    local owned = self:_ownedCount()
    return {
        smallCrosshairSupported = true, smallCrosshairAvailable = self.smallCrosshairAvailable,
        active = self.active, lastStatus = self.lastStatus, ownedFields = owned,
        pendingCleanup = self.restoring and owned or 0, checkInterval = INTERVAL,
        nativeGameVerified = false
    }
end
return Weapon
end)()

--[[============================================================================
    TOXIC UNIVERSAL BYPASS v5.0 — SINGLE FILE DROP-IN
    ----------------------------------------------------------------------------
    USAGE:
    STEP 1: Copy entire file
    STEP 2: Paste at TOP of any .lua file
    STEP 3: Auto-runs — no call needed
    STEP 4: Console shows 3 lines = BYPASS ACTIVE

    VERIFY:    _G.TOXIC_BYPASS_Status()
    RE-APPLY:  _G.TOXIC_BYPASS_Apply()
============================================================================]]

local BYPASS = {}
_G.TOXIC_BYPASS = BYPASS

-- ============================================================================
-- HELPERS
-- ============================================================================
local function NOP() return true end
local function RT()  return true end
local function RF()  return false end
local function R0()  return 0 end
local function RE()  return {} end
local function RES() return "" end

local function valid(o)
    if not o then return false end
    if slua and slua.isValid then
        local ok, v = pcall(slua.isValid, o)
        return ok and v
    end
    return o ~= nil
end

local function mute(obj)
    if type(obj) ~= "table" then return end
    for k, v in pairs(obj) do
        if type(v) == "function" and type(k) == "string" and
            (k:find("Report") or k:find("Send") or k:find("Upload") or
             k:find("Verify") or k:find("Check") or k:find("Validate") or
             k:find("Scan") or k:find("Detect") or k:find("Collect") or
             k:find("Flow") or k:find("Heartbeat") or k:find("Record") or
             k:find("Trace") or k:find("Replay") or k:find("Save")) then
            pcall(function() obj[k] = NOP end)
        end
    end
end

-- ============================================================================
-- PACKET / RPC BLOCKLIST
-- ============================================================================
local BLOCKED_PACKETS = {
    ["ReportPlayer"]=1,["ReportPlayerBehavior"]=1,["ReportSuspicious"]=1,
    ["ReportCheat"]=1,["ReportHack"]=1,["ReportAim"]=1,["ReportESP"]=1,
    ["ReportSpeed"]=1,["ReportWall"]=1,["ReportTeammate"]=1,["ReportVoice"]=1,
    ["ReportBadWord"]=1,["ReportToxic"]=1,["ReportAFK"]=1,["ReportTeamKill"]=1,
    ["ReportUnsporting"]=1,["ReportFeedback"]=1,["ReportPlayerName"]=1,
    ["ReportBug"]=1,["ReportAutoAim"]=1,["ReportWallHack"]=1,["ReportSpeedHack"]=1,
    ["ReportAimFlow"]=1,["ReportHitFlow"]=1,["ReportAttackFlow"]=1,
    ["ReportSecAttackFlow"]=1,["ReportFireArms"]=1,["ReportVerifyInfoFlow"]=1,
    ["ReportMrpcsFlow"]=1,["ReportSecMrpcsFlow"]=1,["ReportPlayerMoveRoute"]=1,
    ["ReportPlayerPosition"]=1,["ReportVehicleMoveFlow"]=1,
    ["ReportSecTgameMovingFlow"]=1,["ReportParachuteData"]=1,
    ["ReportEquipmentFlow"]=1,["ReportCircleFlow"]=1,["ReportPlayersPing"]=1,
    ["ReportPlayerIP"]=1,["ReportPlayerFramePingRecord"]=1,
    ["ReportDSNetSaturation"]=1,["ReportNetContinuousSaturate"]=1,
    ["ReportDSNetRate"]=1,["ReportTeammatHurt"]=1,["ReportMisKillByTeammate"]=1,
    ["ReportForbitPick"]=1,["report_parachute_data"]=1,
    ["ReportCheatDetection"]=1,["ReportViolation"]=1,["ReportSecurityViolation"]=1,
    ["ReportIntegrityFailure"]=1,["ReportModdedFiles"]=1,["ReportSignatureFail"]=1,
    ["AntiCheatReport"]=1,["CheatDetection"]=1,["ViolationReport"]=1,
    ["SecurityViolation"]=1,["IntegrityCheck"]=1,["SignatureVerify"]=1,
    ["tss_sdk_report"]=1,["tss_sdk_ban"]=1,["tss_sdk_kick"]=1,
    ["on_tss_sdk_anti_data"]=1,["TssSdkReport"]=1,["TssSdkBan"]=1,["TssSdkKick"]=1,
    ["CoronaLabReport"]=1,["CoronaLabData"]=1,["RPC_ClientCoronaLab"]=1,
    ["OperationalStats"]=1,["ReportOperationalStats"]=1,["OperationalStatsReport"]=1,
    ["SwiftHawk"]=1,["ClientSwiftHawk"]=1,["ClientSwiftHawkWithParams"]=1,
    ["SwiftHawkReport"]=1,["SwiftHawkData"]=1,
    ["ClientSecMrpcsFlow"]=1,["MrpcsData"]=1,
    ["BanPlayer"]=1,["KickPlayer"]=1,["on_ban_notice"]=1,["on_kick_notice"]=1,
    ["detect_cheat"]=1,["ban_player"]=1,["kick_player"]=1,
    ["report_player"]=1,["report_cheat"]=1,["report_hack"]=1,["report_esp"]=1,
    ["report_aim_bot"]=1,["report_speed_hack"]=1,["report_wall_hack"]=1,
    ["report_modded_files"]=1,["report_memory_exception"]=1,
    ["report_avatar_exception"]=1,["report_script_exception"]=1,
    ["report_lua_violation"]=1,["report_pak_modified"]=1,
    ["report_signature_fail"]=1,["report_integrity_fail"]=1,
    ["report_unrealnet_exception"]=1,["client_anti_cheat_report"]=1,
    ["report_players_ping"]=1,["report_player_ip"]=1,["report_net_saturate"]=1,
    ["ESPDetection"]=1,["ReportESP"]=1,["WallhackReport"]=1,["RenderAnomaly"]=1,
    ["MarkDetection"]=1,["ScreenMarkReport"]=1,["ClientESPReport"]=1,
    ["ESPUsage"]=1,["VisualAnomaly"]=1,["report_wallhack"]=1,["report_render"]=1,
    ["report_screen_mark"]=1,["report_visual_anomaly"]=1,["esp_detection"]=1,
    ["wallhack_detection"]=1,["render_check"]=1,
}

local BLOCKED_RPC = {
    "RPC_Server_ReportPlayer","RPC_Server_ReportCheat",
    "RPC_Server_ReportSuspicious","RPC_Server_ReportBehavior",
    "RPC_Server_ReportAim","RPC_Server_ReportESP",
    "RPC_Server_SwiftHawk","RPC_Server_ClientSwiftHawkWithParams",
    "RPC_Server_ClientSecMrpcsFlow",
    "RPC_Server_ReportSimulateCharacterLocation",
    "RPC_Client_ShootVertifyRes","RPC_ClientCoronaLab",
    "RPC_OperationalStats","RPC_Server_Ban","RPC_Server_Kick",
}

local KILL_SUBSYSTEMS = {
    "AFKReportorSubsystem","ClientDataStatistcsSubsystem","AvatarExceptionSubsystem",
    "ShootVerifySubSystemClient","MemoryCheckSubsystem","SpeedCheckSubsystem",
    "WallCheckSubsystem","FileCheckSubsystem","BehaviorScoreSubsystem",
    "CoronaLabSubsystem","PlayerSecurityInfoSubsystem","ClientCircleFlowSubsystem",
    "ModifierExceptionSubsystem","SimulateCharacterSubsystem",
    "ClientReportPlayerSubsystem","DSReportPlayerSubsystem",
    "ClientHawkEyePatrolSubsystem","DSHawkEyePatrolSubsystem",
    "GameReportSubsystem","ReplaySubsystem","SwiftHawkSubsystem",
    "AntiCheatSubsystem","IntegrityCheckSubsystem","SignatureVerifySubsystem",
    "MD5CheckSubsystem","PakVerifySubsystem","OperationalStatsSubsystem",
    "MrpcsFlowSubsystem","CircleFlowSubsystem",
    "ClientESPDetectionSubsystem","ClientAimTrackingSubsystem",
    "ClientRenderCheckSubsystem","ClientMemoryGuardSubsystem",
    "ClientKernelCheckSubsystem","ClientWallhackDetectionSubsystem",
    "ClientAntiCheatSubsystem","ClientSecMrpcsFlowSubsystem",
}

-- ============================================================================
-- 1) NETWORK + RPC HOOK
-- ============================================================================
function BYPASS.HookNetwork()
    pcall(function()
        if NetUtil and NetUtil.SendPacket and not NetUtil.SendPacket.__TX then
            local orig = NetUtil.SendPacket
            NetUtil.SendPacket = function(name, ...)
                if BLOCKED_PACKETS[name] then return nil end
                return orig(name, ...)
            end
            NetUtil.SendPacket.__TX = true
        end
    end)
    pcall(function()
        if _G.SendRPC and not _G.SendRPC.__TX then
            local orig = _G.SendRPC
            _G.SendRPC = function(rpc, ...)
                if not rpc then return orig(rpc, ...) end
                for _, b in ipairs(BLOCKED_RPC) do
                    if rpc == b then return nil end
                end
                local low = string.lower(tostring(rpc))
                if low:find("report") or low:find("ban") or low:find("kick")
                    or low:find("cheat") or low:find("hack") or low:find("violation")
                    or low:find("verify") or low:find("integrity") then
                    return nil
                end
                return orig(rpc, ...)
            end
            _G.SendRPC.__TX = true
        end
    end)
end

-- ============================================================================
-- 2) HASH / SLUA / MD5
-- ============================================================================
function BYPASS.KillHashes()
    pcall(function()
        if slua and slua.getSignature then slua.getSignature = R0 end
        local loader = package.loaded["slua.loader"] or rawget(_G, "slua_loader")
        if loader then
            loader.verifyBytecode = RT
            loader.checkIntegrity = RT
            if loader.disableSignatureCheck then loader.disableSignatureCheck = RT end
        end
        local ser = package.loaded["slua.serialize"]
        if ser then ser.check = RT; ser.verify = RT end
        if jit and jit.attach then jit.attach(function() end, "bc") end
        if _G.slua_verify then _G.slua_verify = RT end
        if _G.check_slua_integrity then _G.check_slua_integrity = RT end

        local KSL = import("KismetSystemLibrary")
        if KSL then
            KSL.ExecuteConsoleCommand(nil, "pak.DisablePakSignatureCheck 1")
            KSL.ExecuteConsoleCommand(nil, "pakchunk.EnableSignatureCheck 0")
            KSL.ExecuteConsoleCommand(nil, "s.VerifyPak 0")
            KSL.ExecuteConsoleCommand(nil, "sig.Check 0")
            KSL.ExecuteConsoleCommand(nil, "security.DisableChecks 1")
        end
        local CMode = import("CreativeModeBlueprintLibrary")
        if CMode then
            CMode.MD5HashByteArray = function() return "00000000000000000000000000000000" end
            CMode.MD5HashFile      = function() return "00000000000000000000000000000000" end
            CMode.GetContentDiffData = function() return true, "OK" end
            CMode.VerifyFileIntegrity = RT
        end
        if _G.MD5Hash then _G.MD5Hash = function() return "00000000000000000000000000000000" end end
        if _G.CRC32   then _G.CRC32   = function() return 0 end end
        if _G.SHA1    then _G.SHA1    = function() return "BYPASS" end end

        local fhc = package.loaded["common.file_hash_checker"]
        if fhc then
            fhc.CheckFileMD5 = RT; fhc.VerifyAll = RT
            fhc.GetHash = function() return "BYPASS" end
        end
        local STExtra = import("STExtraBlueprintFunctionLibrary")
        if STExtra then
            STExtra.CheckMD5 = RT
            STExtra.GetMD5 = function() return "BYPASS" end
            STExtra.VerifyFile = RT
        end
    end)
end

-- ============================================================================
-- 3) TSS SDK
-- ============================================================================
function BYPASS.KillTSS()
    pcall(function()
        local tss = package.loaded["TssSdk"] or _G.TssSdk
        if not tss then return end
        local origRecv = tss.OnRecvData
        tss.OnRecvData = function(data)
            if type(data) == "string" then
                local low = string.lower(data)
                if low:find("report", 1, true) or low:find("exception", 1, true) or
                   low:find("cheat", 1, true) or low:find("violation", 1, true) or
                   low:find("hack", 1, true) or low:find("verify", 1, true) then
                    return
                end
            end
            if origRecv then pcall(origRecv, data) end
        end
        tss.GetFileMD5           = function() return "00000000000000000000000000000000" end
        tss.VerifyFileSignature  = RT
        tss.SendReportInfo       = NOP
        tss.ScanMemory           = RT
        tss.IsEmulator           = RF
        tss.GetTssSdkReportInfo  = RES
        tss.CheckEnvironment     = RT
        tss.VerifyProcess        = RT
        tss.ReportBan            = NOP
        tss.ReportCheat          = NOP
        tss.BanPlayer            = NOP
        tss.KickPlayer           = NOP
    end)
end

-- ============================================================================
-- 4) LOGS / SCREENSHOT / ANALYTICS
-- ============================================================================
function BYPASS.KillLogs()
    pcall(function()
        local SMTD = import("ScreenshotMTDer")
        if SMTD then
            SMTD.MTDePicture = RES
            SMTD.ReMTDePicture = RES
            SMTD.HasCaptured = RT
            SMTD.TakeScreenshot = NOP
        end
        local TLog = package.loaded["TLog"] or _G.TLog
        if TLog then
            TLog.Info, TLog.Warning, TLog.Error, TLog.Debug = NOP,NOP,NOP,NOP
            TLog.Report, TLog.Send, TLog.Flush = NOP,NOP,NOP
        end
        local CS = package.loaded["CrashSight"] or _G.CrashSight
        if CS then
            CS.ReportException = NOP; CS.SetCustomData = NOP; CS.Log = NOP
            CS.SendCrash = NOP; CS.ReportUserException = NOP
        end
        local GR = package.loaded["GameLua.Mod.BaseMod.GamePlay.GameReport.GameReportUtils"]
        if GR then
            GR.BugglyPostExceptionFull = RF
            GR.CheckCanBugglyPostException = RF
            GR.ReplayReportData = NOP; GR.ReportGameException = NOP; GR.PostException = NOP
        end
        local CTR = package.loaded["client.slua.logic.report.ClientToolsReport"]
        if CTR then
            CTR.SendReport = NOP; CTR.SendException = NOP; CTR.UploadLog = NOP
        end
        for _, sdk in ipairs({"Firebase","Adjust","AppsFlyer","FacebookAnalytics","GameAnalytics"}) do
            local s = _G[sdk]
            if s then
                s.logEvent = NOP; s.trackEvent = NOP
                s.setEnabled = RF; s.sendEvent = NOP; s.report = NOP
            end
        end
    end)
end

-- ============================================================================
-- 5) SKIN / PUFFER REPORT
-- ============================================================================
function BYPASS.KillSkinReports()
    pcall(function()
        local PT = package.loaded["client.slua.logic.download.report.puffer_tlog"]
        if PT then
            PT.ReportEvent = NOP; PT.ReportDownloadResult = NOP
            PT.ReportODPTDError = NOP; PT.ReportSkinError = NOP
        end
        local AV = package.loaded["AvatarUtils"]
        if AV then
            AV.CheckIsWeaponInBlackList = RF
            AV.IsValidAvatar = RT
            AV.CheckAvatarIntegrity = RT
            AV.ReportInvalidAvatar = NOP
        end
        local EQ = package.loaded["client.slua.logic.report.EquipmentExceptionReport"]
        if EQ then EQ.Report = NOP; EQ.SendException = NOP end
    end)
end

-- ============================================================================
-- 6) SUBSYSTEM KILLER
-- ============================================================================
function BYPASS.KillSubsystems()
    pcall(function()
        local mgr = require("GameLua.GameCore.Module.Subsystem.SubsystemMgr")
        if not mgr then return end
        for _, name in ipairs(KILL_SUBSYSTEMS) do
            local sub = mgr:Get(name)
            if sub then
                mute(sub)
                for _, tm in ipairs({"timer","heartbeatTimer","reportTimer","ReportPingDelayTimer"}) do
                    if sub[tm] then pcall(function() sub:RemoveGameTimer(sub[tm]) end) end
                end
                sub.bBanned = false
                sub.bKicked = false
                sub.bSuspended = false
                sub.BanCount = 0
                sub.WarningCount = 0
                sub.SuspicionScore = 0
            end
        end
    end)
    pcall(function()
        local AX = package.loaded["GameLua.Mod.Library.GamePlay.Avatar.Exception.AvatarExceptionPlayerInst"]
        if AX then
            AX.CheckAvatarException = NOP; AX.CheckAvatarExceptionOnce = NOP
            AX.ReportAvatarException = NOP
            AX.CheckSlotMeshVisible = RF; AX.CheckPawnVisible = RF
            AX.CheckCanBugglyPostException = RF
        end
    end)
    pcall(function()
        local RR = package.loaded["client.slua.logic.replay.logic_report_replay"]
        if RR then
            RR.ReportReplay = NOP; RR.SendReportReq = NOP; RR.UploadReplay = NOP
        end
    end)
end

-- ============================================================================
-- 7) HIGGS BOSON
-- ============================================================================
function BYPASS.KillHiggs()
    pcall(function()
        local HBC = require("GameLua.Mod.BaseMod.Common.Security.HiggsBosonComponent")
        if HBC then
            local methods = {
                "ControlMHActive","Tick","OnTick","MHActiveLogic","TriggerAvatarCheck",
                "StartAvatarCheck","ReportItemID","ReceiveAnyDamage","OnWeaponHitRecord",
                "ShowSecurityAlert","ServerReportAvatar","ClientReportNetAvatar",
                "SendHisarData","ValidateSecurityData","StaticShowSecurityAlertInDev",
                "DisableHiggsBoson","CheckMHActive","ReportViolation",
                "ProcessSecurityEvent","ValidatePlayer","CheckIntegrity"
            }
            for _, m in ipairs(methods) do
                if HBC[m] then HBC[m] = NOP end
            end
            HBC.GetNetAvatarItemIDs = RE
            HBC.GetCurWeaponSkinID  = R0
            HBC.IsMHActive          = RF
            HBC.bMHActive           = false
            HBC.bCallPreReplication = false
            if HBC.BlackList then
                for k in pairs(HBC.BlackList) do HBC.BlackList[k] = nil end
            end
        end
        _G.BlackList = {}

        local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
        if valid(pc) then
            if pc.HiggsBoson then
                pc.HiggsBoson.bMHActive = false
                pc.HiggsBoson.bCallPreReplication = false
                if pc.HiggsBoson.ControlMHActive then
                    pcall(function() pc.HiggsBoson:ControlMHActive(0) end)
                end
            end
            if pc.HiggsBosonComponent then
                pc.HiggsBosonComponent.bMHActive = false
                pc.HiggsBosonComponent.bCallPreReplication = false
                pcall(function() pc.HiggsBosonComponent:ControlMHActive(0) end)
            end
        end

        if _G.AvatarCheckCallback then
            _G.AvatarCheckCallback.StartAvatarCheck = NOP
            _G.AvatarCheckCallback.OnReportItemID = NOP
            _G.AvatarCheckCallback.PostPlayerControllerLoginInit = function(pc2)
                if valid(pc2) then
                    if pc2.HiggsBosonComponent then
                        pcall(function() pc2.HiggsBosonComponent:ControlMHActive(0) end)
                        pc2.HiggsBosonComponent.bMHActive = false
                    end
                    if pc2.HiggsBoson then
                        pcall(function() pc2.HiggsBoson:ControlMHActive(0) end)
                        pc2.HiggsBoson.bMHActive = false
                    end
                end
            end
        end
    end)
end

-- ============================================================================
-- 8) GAMEPLAY CALLBACKS
-- ============================================================================
local FLOW_CALLBACKS = {
    "ReportAttackFlow","ReportSecAttackFlow","ReportFireArms",
    "ReportVerifyInfoFlow","ReportMrpcsFlow","ReportPlayerBehavior",
    "ReportTeammatHurt","ReportMisKillByTeammate","ReportForbitPick",
    "ReportPlayerMoveRoute","ReportPlayerPosition","ReportVehicleMoveFlow",
    "ReportSecTgameMovingFlow","ReportParachuteData","ReportEquipmentFlow",
    "ReportAimFlow","ReportHitFlow","ReportCircleFlow","ReportPlayersPing",
    "ReportPlayerIP","ReportPlayerFramePingRecord","ReportDSNetSaturation",
    "ReportNetContinuousSaturate","ReportDSNetRate","SendTssSdkAntiDataToLobby",
    "SendClientStats","SendServerAvgTickDelta","ClientSecMrpcsFlow",
    "SwiftHawk","ClientSwiftHawk","ClientSwiftHawkWithParams",
    "ReportESP","ReportWallhack","ReportRenderAnomaly","CheckESP",
    "CheckWallhack","CheckRender","OnESPDetected","OnWallhackDetected",
    "OnRenderAnomaly","ValidateScreenMark","CheckScreenMark","ReportScreenMark",
    "BanPlayer","BanUser","ReportBan","SendBanReport","DetectBan","CheckBan",
    "ValidateBan","ProcessBan","BanKick","KickPlayer","ForceLogout",
    "DisconnectPlayer","ReportSuspicious","ReportCheat","ReportHack",
    "OnCheatDetected","OnHackDetected","OnViolationDetected","AntiCheatReport",
    "CheatDetection","ViolationReport","SecurityViolation","IntegrityCheck",
    "SignatureVerify","TssSdkReport","TssSdkBan","TssSdkKick",
}

function BYPASS.KillGameplayCallbacks()
    pcall(function()
        if not _G.GameplayCallbacks then _G.GameplayCallbacks = {} end
        local GC = _G.GameplayCallbacks
        for _, f in ipairs(FLOW_CALLBACKS) do
            GC[f] = NOP
            if _G[f] then _G[f] = NOP end
        end
        GC.CheckReportSecAttackFlowWithAttackFlow = RF
        GC.CheckReportSecAttackFlow = RF
        if _G.CheckReportSecAttackFlowWithAttackFlow then _G.CheckReportSecAttackFlowWithAttackFlow = RF end
        if _G.CheckReportSecAttackFlow then _G.CheckReportSecAttackFlow = RF end
        for _, f in ipairs({"IsEnableReportMrpcsInCircleFlow","IsEnableReportMrpcsInPartCircleFlow",
                            "IsEnableReportMrpcsFlow","IsEnableReportAttackFlow",
                            "IsEnableReportHitFlow","IsEnableReportCircleFlow"}) do
            if _G[f] then _G[f] = RF end
        end
        _G.ShowBanNotice     = NOP
        _G.ShowKickNotice    = NOP
        _G.ProcessBanNotice  = NOP
        _G.HandleBanNotice   = NOP
        _G.ShowBanUI         = NOP
        _G.ShowKickUI        = NOP

        local orig = GC.OnDSPlayerStateChanged
        GC.OnDSPlayerStateChanged = function(uid, state, bPure, bSafe, param)
            local s = state and string.lower(tostring(state)) or ""
            local danger = {
                ["cheatdetected"]=1,["connectionlost"]=1,["connectiontimeout"]=1,
                ["connectionexception"]=1,["netdrivererror"]=1,["banned"]=1,
                ["kicked"]=1,["suspended"]=1,["violationdetected"]=1,
                ["integrityfailure"]=1,["securityviolation"]=1,["reportdetected"]=1
            }
            if danger[s] then return end
            if orig then pcall(orig, uid, state, bPure, bSafe, param) end
        end
        GC.OnPlayerNetConnectionClosed = NOP
        GC.OnPlayerActorChannelError   = NOP
        GC.OnPlayerRPCValidateFailed   = NOP
        GC.OnPlayerSpectateException   = NOP
        GC.OnShutdownAfterError        = NOP
    end)
end

-- ============================================================================
-- 9) BAN POPUP UI
-- ============================================================================
function BYPASS.KillBanUI()
    pcall(function()
        local banUI = {
            "client.slua.umg.BanNoticeUI",
            "client.slua.umg.KickNoticeUI",
            "GameLua.Mod.BaseMod.Client.UI.BanUI",
        }
        for _, path in ipairs(banUI) do
            local mod = package.loaded[path]
            if not mod then
                local ok, loaded = pcall(require, path)
                if ok and loaded then mod = loaded end
            end
            if mod and type(mod) == "table" then
                for k, v in pairs(mod) do
                    if type(v) == "function" and type(k) == "string" and k:find("Show") then
                        pcall(function() mod[k] = NOP end)
                    end
                end
            end
        end
    end)
end

-- ============================================================================
-- 10) ENV FLAGS
-- ============================================================================
function BYPASS.KillEnvFlags()
    pcall(function()
        for _, flag in ipairs({
            "ENABLE_REPORT","ENABLE_ANTI_CHEAT","ENABLE_SECURITY",
            "ENABLE_TELEMETRY","ENABLE_ANALYTICS","ENABLE_CRASH_REPORT",
            "ENABLE_PERFORMANCE_REPORT"
        }) do
            if _G[flag] then _G[flag] = false end
        end
    end)
end

-- ============================================================================
-- 11) GLOBAL SWEEP
-- ============================================================================
function BYPASS.Sweep()
    local needles = {
        "verify","integrity","signature","filecheck","file_check",
        "hashcheck","hash_check","tss","security","report"
    }
    local seen = {}
    pcall(function()
        local function watch(m)
            if type(m) ~= "table" or seen[m] then return end
            seen[m] = true
            mute(m)
        end
        for key, mod in pairs(package.loaded) do
            if type(key) == "string" then
                local low = string.lower(key)
                for _, n in ipairs(needles) do
                    if string.find(low, n, 1, true) then watch(mod) break end
                end
            end
        end
        for key, mod in pairs(_G) do
            if type(key) == "string" then
                local low = string.lower(key)
                for _, n in ipairs(needles) do
                    if string.find(low, n, 1, true) then watch(mod) break end
                end
            end
        end
    end)
end

-- ============================================================================
-- 12) ANTI-FORENSICS
-- ============================================================================
function BYPASS.AntiForensics()
    pcall(function()
        if debug and debug.getinfo then
            local orig = debug.getinfo
            debug.getinfo = function(level, what)
                local info = orig(level, what)
                if info and info.source then
                    local src = info.source
                    if string.find(src, "BRPlayerCharacterBase", 1, true)
                        or string.find(src, "AegisShell", 1, true)
                        or string.find(src, "TOXIC", 1, true) then
                        info.source = "ProtectedSource"
                        info.short_src = "ProtectedSource"
                    end
                end
                return info
            end
        end
        if debug then
            if debug.sethook   then debug.sethook   = function() end end
            if debug.getlocal  then debug.getlocal  = function() end end
            if debug.setupvalue then debug.setupvalue = function() end end
        end
        if string and string.dump then
            string.dump = function() return "" end
        end
    end)
end

-- ============================================================================
-- 13) HUM
-- ============================================================================
function BYPASS.Hum()
    _G.TX_HB   = math.random(15, 45)
    _G.TX_JIT  = math.random(-12, 18)
    _G.TX_KD   = 0.9 + math.random() * 1.9
    _G.TX_HD   = 9 + math.random() * 22
end

-- ============================================================================
-- MASTER APPLY
-- ============================================================================
function BYPASS.ApplyAll()
    BYPASS.HookNetwork()
    BYPASS.KillHashes()
    BYPASS.KillTSS()
    BYPASS.KillLogs()
    BYPASS.KillSkinReports()
    BYPASS.KillSubsystems()
    BYPASS.KillHiggs()
    BYPASS.KillGameplayCallbacks()
    BYPASS.KillBanUI()
    BYPASS.KillEnvFlags()
    BYPASS.Sweep()
    BYPASS.AntiForensics()
    BYPASS.Hum()
end

-- ============================================================================
-- BOOT
-- ============================================================================
_G.LicenseValid = true
_G.ModsEnabled  = true
_G.CompleteBypassStarted = true

pcall(function()
    print("[TOXIC v5.0] Applying all layers...")
    BYPASS.ApplyAll()
    print("[TOXIC v5.0] Layer 1-13 ACTIVE")
end)

-- ============================================================================
-- CONTINUOUS MONITOR (5s)
-- ============================================================================
pcall(function()
    local ticker = require("common.time_ticker")
    if not ticker then return end

    local function loop()
        pcall(function()
            if NetUtil and NetUtil.SendPacket and not NetUtil.SendPacket.__TX then
                BYPASS.HookNetwork()
            end
            if _G.SendRPC and not _G.SendRPC.__TX then
                BYPASS.HookNetwork()
            end
            local pc = slua_GameFrontendHUD and slua_GameFrontendHUD:GetPlayerController()
            if valid(pc) then
                if pc.HiggsBoson then
                    pc.HiggsBoson.bMHActive = false
                    pc.HiggsBoson.bCallPreReplication = false
                end
                if pc.HiggsBosonComponent then
                    pc.HiggsBosonComponent.bMHActive = false
                    pc.HiggsBosonComponent.bCallPreReplication = false
                end
            end
            BYPASS.KillSubsystems()
            BYPASS.KillGameplayCallbacks()
        end)
    end

    if ticker.AddTimerOnce then ticker.AddTimerOnce(3.0, loop) end
    if ticker.AddTimerLoop then ticker.AddTimerLoop(0, loop, -1, 5.0) end
end)

-- ============================================================================
-- RE-APPLY ON MATCH ENTER
-- ============================================================================
pcall(function()
    if EventSystem and EventSystem.registEvent then
        if EVENTTYPE_LOBBY and EVENTID_ENTER_GAME_BEGIN then
            EventSystem:registEvent(EVENTTYPE_LOBBY, EVENTID_ENTER_GAME_BEGIN, function()
                pcall(BYPASS.ApplyAll)
            end)
        end
    end
end)

-- ============================================================================
-- PUBLIC API
-- ============================================================================
_G.StartBypass_Complete  = BYPASS.ApplyAll
_G.TOXIC_BYPASS_Apply    = BYPASS.ApplyAll
_G.TOXIC_BYPASS_Status   = function()
    return {
        network = NetUtil and NetUtil.SendPacket and NetUtil.SendPacket.__TX == true or false,
        rpc     = _G.SendRPC and _G.SendRPC.__TX == true or false,
        started = _G.CompleteBypassStarted == true,
    }
end

print("[TOXIC v5.0] BYPASS READY - drop-in safe")

-- ========================================================================
-- 7. OPTIONAL LUA INTEGRITY CHECK HOOKS
-- ========================================================================

local ShayanBypassFeatures = (function()
local Bypass = {}
Bypass.__index = Bypass
local INTERVAL = 1
local BOOLEAN_KEYS = {
    'CheckMD5', 'CheckFileMD5', 'CheckFileIntegrity', 'VerifyFileIntegrity',
    'VerifyFile', 'VerifyAll', 'VerifyFileSignature', 'VerifySignature', 'slua_verify', 'check_slua_integrity'
}
local SUBSYSTEMS = {
    'MD5CheckSubsystem', 'FileCheckSubsystem', 'AssetCheckSubsystem',
    'IntegrityCheckSubsystem', 'SignatureVerifySubsystem', 'PakCheckSubsystem', 'PakVerifySubsystem'
}
local GROUPS = {
    { kind = 'loaded', name = 'common.file_hash_checker', fallback = 'FileHashChecker', keys = { 'CheckFileMD5', 'VerifyAll' } },
    { kind = 'imported', name = 'CreativeModeBlueprintLibrary', keys = { 'VerifyFileIntegrity' } },
    { kind = 'imported', name = 'STExtraBlueprintFunctionLibrary', fallback = 'STExtra', keys = { 'CheckMD5', 'VerifyFile' } },
    { kind = 'loaded', name = 'TssSdk', fallback = 'TssSdk', keys = { 'VerifyFileSignature', 'CheckIntegrity', 'CheckKernel', 'VerifyBoot' } },
    { kind = 'slua', name = 'loader', keys = { 'verifyBytecode', 'checkIntegrity' } },
    { kind = 'slua', name = 'serialize', keys = { 'check', 'verify' } }
}
for i = 1, #SUBSYSTEMS do
    GROUPS[#GROUPS + 1] = { kind = 'subsystem', name = SUBSYSTEMS[i], keys = BOOLEAN_KEYS }
end
local function finite(value) return type(value) == 'number' and value == value and value > -math.huge and value < math.huge end
local function field(owner, key) return owner[key] end
local function assign(owner, key, value) owner[key] = value end
local function read(owner, key)
    if type(owner) ~= 'table' then return nil end
    local ok, value = pcall(field, owner, key)
    if ok then return value end
end
local function exposed(value) if type(value) == 'table' then return value end end

function Bypass.new(env)
    local slots = {}
    for group = 1, #GROUPS do
        local keys = GROUPS[group].keys
        for i = 1, #keys do slots[#slots + 1] = { group = group, key = keys[i] } end
    end
    return setmetatable({
        env = env or _G, slots = slots, settings = nil, requested = false,
        enabled = false, active = false, disposed = false, nextCheck = 0, lastTime = nil,
        bypassAvailable = nil, lastStatus = 'inactive', matchedSlots = 0,
        reconcileCount = 0, updating = false
    }, Bypass)
end

function Bypass:_wanted()
    return not self.disposed and type(self.settings) == 'table' and self.settings.bypass == true
end

function Bypass:_owners()
    local result = {}
    local loaded = read(read(self.env, 'package'), 'loaded')
    for i = 1, #GROUPS do
        local group = GROUPS[i]
        local owner
        if group.kind == 'loaded' then
            owner = exposed(read(loaded, group.name)) or exposed(read(self.env, group.fallback))
        elseif group.kind == 'slua' then
            owner = exposed(read(read(self.env, 'slua'), group.name))
        elseif group.kind == 'subsystem' then
            owner = exposed(read(self.env, group.name)) or exposed(read(loaded, group.name))
        else
            owner = exposed(read(self.env, group.name))
            if not owner then
                local importer = read(self.env, 'import')
                if type(importer) == 'function' then
                    local ok, value = pcall(importer, group.name)
                    if ok then owner = exposed(value) end
                end
            end
            if not owner and group.fallback then owner = exposed(read(self.env, group.fallback)) end
        end
        result[i] = owner
    end
    return result
end

function Bypass:_recordCount()
    local count = 0
    for i = 1, #self.slots do if self.slots[i].record then count = count + 1 end end
    return count
end

function Bypass:_findRecord(owner, key)
    for i = 1, #self.slots do
        local record = self.slots[i].record
        if record and record.owner == owner and record.key == key then return record end
    end
end

function Bypass:_blocked(owner, key)
    for i = 1, #self.slots do
        local slot = self.slots[i]
        if slot.blockedOwner == owner and slot.key == key then return true end
    end
    return false
end

function Bypass:_stillBound(owners, owner, key)
    for i = 1, #self.slots do
        local slot = self.slots[i]
        if slot.key == key and owners[slot.group] == owner then return true end
    end
    return false
end

function Bypass:_restoreSlot(slot)
    local record = slot.record
    if not record then return true end
    record.active = false
    local ok, current = pcall(field, record.owner, record.key)
    if not ok then return false end
    if current == record.wrapper then
        pcall(assign, record.owner, record.key, record.original)
        ok, current = pcall(field, record.owner, record.key)
        if not ok or current == record.wrapper then return false end
    end
    if current ~= record.original then
        slot.blockedOwner, slot.blockReason = record.owner, 'external_replacement'
    end
    slot.record = nil
    return true
end

function Bypass:_restoreAll()
    self.enabled, self.active = false, false
    for i = 1, #self.slots do
        local record = self.slots[i].record
        if record then record.active = false end
    end
    local restored = true
    for i = #self.slots, 1, -1 do
        if not self:_restoreSlot(self.slots[i]) then restored = false end
    end
    return restored
end

function Bypass:_stop(reason)
    local restored = self:_restoreAll()
    self.bypassAvailable = false
    self.lastStatus = restored and reason or 'restore_pending'
    return false
end

function Bypass:_reconcile()
    self.reconcileCount = self.reconcileCount + 1
    self.enabled, self.active = false, false
    local owners = self:_owners()
    self.matchedSlots = 0
    for i = 1, #self.slots do
        local slot = self.slots[i]
        local record = slot.record
        if record then
            local ok, current = pcall(field, record.owner, record.key)
            if not ok then return self:_stop('export_read_failed') end
            if current ~= record.wrapper then
                record.active = false
                slot.record = nil
                slot.blockedOwner, slot.blockReason = record.owner, 'external_replacement'
            elseif owners[slot.group] ~= record.owner then
                if not self:_restoreSlot(slot) then return self:_stop('restore_pending') end
            end
        end
    end
    if not self:_wanted() then return self:_stop('inactive') end
    for i = 1, #self.slots do
        local slot = self.slots[i]
        local owner = owners[slot.group]
        if slot.blockedOwner and not self:_stillBound(owners, slot.blockedOwner, slot.key) then
            slot.blockedOwner, slot.blockReason = nil, nil
        end
        if owner and not self:_blocked(owner, slot.key) then
            local current = read(owner, slot.key)
            if type(current) == 'function' then
                self.matchedSlots = self.matchedSlots + 1
                if not self:_findRecord(owner, slot.key) then
                    local record = { owner = owner, key = slot.key, original = current, active = false }
                    local orig = current
                    record.wrapper = function(...)
                        if record.active and self.enabled then return true end
                        return orig(...)
                    end
                    slot.record = record
                    local ok = pcall(assign, owner, slot.key, record.wrapper)
                    local readOK, value = pcall(field, owner, slot.key)
                    if not ok or not readOK or value ~= record.wrapper then
                        slot.blockedOwner, slot.blockReason = owner, 'install_failed'
                        return self:_stop('install_failed')
                    end
                    if not self:_wanted() then return self:_stop('inactive') end
                end
            end
        end
    end
    for i = 1, #self.slots do
        local slot = self.slots[i]
        local record = slot.record
        if record then
            local ok, current = pcall(field, record.owner, record.key)
            if not ok then return self:_stop('export_read_failed') end
            if current ~= record.wrapper then
                record.active = false
                slot.record = nil
                slot.blockedOwner, slot.blockReason = record.owner, 'external_replacement'
                return self:_stop('external_replacement')
            end
        end
    end
    if not self:_wanted() then return self:_stop('inactive') end
    local count = self:_recordCount()
    if count > 0 then
        local currentOwners = self:_owners()
        for i = 1, #self.slots do
            local slot = self.slots[i]
            local record = slot.record
            if record and currentOwners[slot.group] ~= record.owner then
                return self:_stop('binding_changed')
            end
        end
        if not self:_wanted() then return self:_stop('inactive') end
    end
    self.enabled = count > 0
    self.active = self.enabled
    self.bypassAvailable = self.active
    for i = 1, #self.slots do
        local record = self.slots[i].record
        if record then record.active = self.enabled end
    end
    self.lastStatus = count == 0 and 'no_lua_boolean_exports'
        or (self.matchedSlots < #self.slots and 'partial_lua_boolean_exports' or 'lua_boolean_exports_installed')
    return self.active
end

function Bypass:update(settings, now)
    if self.disposed or self.updating then return false end
    local previous = self.requested
    self.settings = type(settings) == 'table' and settings or nil
    self.requested = self:_wanted()
    if not self.requested then
        self.enabled, self.active = false, false
        if previous then
            for i = 1, #self.slots do
                local slot = self.slots[i]
                if slot.blockReason == 'install_failed' then slot.blockedOwner, slot.blockReason = nil, nil end
            end
        end
        if self:_recordCount() == 0 then self.lastStatus = 'inactive' return false end
        if previous or (finite(now) and now >= self.nextCheck) then
            if finite(now) then self.nextCheck = now + INTERVAL end
            return self:_stop('inactive')
        end
        return false
    end
    if not finite(now) then
        if self.enabled or not previous then return self:_stop('clock_unavailable') end
        self.lastStatus = self:_recordCount() > 0 and 'restore_pending' or 'clock_unavailable'
        return false
    end
    if self.lastTime and now < self.lastTime then
        self.lastTime, self.nextCheck = now, now + INTERVAL
        return self.active
    end
    self.lastTime = now
    if not previous then self.nextCheck = now end
    if now < self.nextCheck then return self.active end
    self.nextCheck = now + INTERVAL
    if not self.enabled and self:_recordCount() > 0 and not self:_restoreAll() then
        self.lastStatus = 'restore_pending'
        return false
    end
    self.updating = true
    local ok, value = pcall(self._reconcile, self)
    self.updating = false
    if not ok then return self:_stop('reconcile_failed') end
    return value
end

function Bypass:dispose()
    self.disposed, self.requested, self.enabled = true, false, false
    self.settings = nil
    local restored = self:_restoreAll()
    self.bypassAvailable = false
    self.lastStatus = restored and 'disposed' or 'restore_pending'
    return restored
end

function Bypass:getStatus()
    local count = self:_recordCount()
    local conflicts = 0
    for i = 1, #self.slots do if self.slots[i].blockedOwner then conflicts = conflicts + 1 end end
    local active = self.enabled and self:_wanted() and count > 0
    return {
        enabled = self.requested, active = active, bypassAvailable = self.bypassAvailable,
        lastStatus = self.lastStatus, ownedHooks = count, installedCount = count,
        appliedHooks = active and count or 0, pendingCleanup = not active and count or 0,
        restorePending = not active and count > 0, configuredSlots = #self.slots,
        matchedSlots = self.matchedSlots, blockedSlots = conflicts, reconcileCount = self.reconcileCount,
        coverage = 'lua_boolean_exports_only', sourceMigration = 'partial',
        nativeInterceptionVerified = false, serverVerification = false
    }
end

return Bypass
end)()

-- Automatic screenshot/data upload module removed for privacy and performance.

-- ========================================================================
-- 8. LOGIN CONFIGURATION
-- ========================================================================

local ShayanLicenseConfig = {
    -- HTTPS key verification endpoint from the supplied Lua.
    -- This must be a JSON POST API; a normal website landing page is not enough.
    url = 'https://kuro-api-pannel.vercel.app/api/connect',

    -- AUTO-FEEDBACK BOT: paste your bot/webhook URL and token here.
    feedbackUrl = 'PASTE_YOUR_BOT_FEEDBACK_URL_HERE',
    feedbackToken = 'PASTE_YOUR_BOT_TOKEN_HERE',

    game = 'PUBG',
    timeout = 12,
    clockSkew = 120,
}

-- ========================================================================
-- 9. LOGIN, EXPIRY AND TOKEN VALIDATION
-- ========================================================================

local ShayanLicenseCore = (function()
local Primitives = (function()
local floor, abs, max = math.floor, math.abs, math.max
local byte, char, format = string.byte, string.char, string.format
local U32 = 4294967296
local AND, XOR = {}, {}
for a = 0, 15 do
    for b = 0, 15 do
        local av, bv, both, different, place = a, b, 0, 0, 1
        for _ = 1, 4 do
            local x, y = av % 2, bv % 2
            if x == 1 and y == 1 then both = both + place end
            if x ~= y then different = different + place end
            av, bv, place = floor(av / 2), floor(bv / 2), place * 2
        end
        AND[a * 16 + b], XOR[a * 16 + b] = both, different
    end
end
local function bitop(a, b, lookup)
    local value, place = 0, 1
    for _ = 1, 8 do
        value = value + lookup[(a % 16) * 16 + b % 16] * place
        a, b, place = floor(a / 16), floor(b / 16), place * 16
    end
    return value
end
local function band(a, b) return bitop(a, b, AND) end
local function bxor(a, b) return bitop(a, b, XOR) end
local function rol(value, amount)
    local divisor = 2 ^ (32 - amount)
    return (value % divisor) * 2 ^ amount + floor(value / divisor)
end
local function little32(value)
    return char(value % 256, floor(value / 256) % 256,
        floor(value / 65536) % 256, floor(value / 16777216) % 256)
end
local K = {
    0xd76aa478,0xe8c7b756,0x242070db,0xc1bdceee,0xf57c0faf,0x4787c62a,0xa8304613,0xfd469501,
    0x698098d8,0x8b44f7af,0xffff5bb1,0x895cd7be,0x6b901122,0xfd987193,0xa679438e,0x49b40821,
    0xf61e2562,0xc040b340,0x265e5a51,0xe9b6c7aa,0xd62f105d,0x02441453,0xd8a1e681,0xe7d3fbc8,
    0x21e1cde6,0xc33707d6,0xf4d50d87,0x455a14ed,0xa9e3e905,0xfcefa3f8,0x676f02d9,0x8d2a4c8a,
    0xfffa3942,0x8771f681,0x6d9d6122,0xfde5380c,0xa4beea44,0x4bdecfa9,0xf6bb4b60,0xbebfbc70,
    0x289b7ec6,0xeaa127fa,0xd4ef3085,0x04881d05,0xd9d4d039,0xe6db99e5,0x1fa27cf8,0xc4ac5665,
    0xf4292244,0x432aff97,0xab9423a7,0xfc93a039,0x655b59c3,0x8f0ccc92,0xffeff47d,0x85845dd1,
    0x6fa87e4f,0xfe2ce6e0,0xa3014314,0x4e0811a1,0xf7537e82,0xbd3af235,0x2ad7d2bb,0xeb86d391
}
local SHIFT = { 7, 12, 17, 22, 5, 9, 14, 20, 4, 11, 16, 23, 6, 10, 15, 21 }
local function md5_raw(input)
    assert(type(input) == "string", "MD5 input must be a string")
    local size = #input
    local message = input .. char(128) .. string.rep(char(0), (55 - size) % 64)
        .. little32((size * 8) % U32) .. little32(floor(size / 536870912))
    local h0, h1, h2, h3 = 0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476
    local words = {}
    for offset = 1, #message, 64 do
        for j = 0, 15 do
            local a, b, c, d = byte(message, offset + j * 4, offset + j * 4 + 3)
            words[j] = a + b * 256 + c * 65536 + d * 16777216
        end
        local a, b, c, d = h0, h1, h2, h3
        for i = 0, 63 do
            local f, g, shiftBase
            if i < 16 then
                f, g, shiftBase = band(b, c) + band(U32 - 1 - b, d), i, 0
            elseif i < 32 then
                f, g, shiftBase = band(d, b) + band(U32 - 1 - d, c), (5 * i + 1) % 16, 4
            elseif i < 48 then
                f, g, shiftBase = bxor(bxor(b, c), d), (3 * i + 5) % 16, 8
            else
                local bOrNotD = U32 - 1 - band(U32 - 1 - b, d)
                f, g, shiftBase = bxor(c, bOrNotD), (7 * i) % 16, 12
            end
            local nextB = (b + rol((a + f + K[i + 1] + words[g]) % U32,
                SHIFT[shiftBase + i % 4 + 1])) % U32
            a, b, c, d = d, nextB, b, c
        end
        h0, h1, h2, h3 = (h0 + a) % U32, (h1 + b) % U32, (h2 + c) % U32, (h3 + d) % U32
    end
    return little32(h0) .. little32(h1) .. little32(h2) .. little32(h3)
end
local function hex(input)
    return (input:gsub(".", function(c) return format("%02x", byte(c)) end))
end
local function md5(input) return hex(md5_raw(input)) end
local function form_encode(input)
    assert(type(input) == "string", "Form value must be a string")
    return (input:gsub("[^A-Za-z0-9%-%._~ ]", function(c)
        return format("%%%02X", byte(c))
    end):gsub(" ", "+"))
end
local function constant_time_equal(a, b)
    if type(a) ~= "string" or type(b) ~= "string" then return false end
    local difference = abs(#a - #b)
    for i = 1, max(#a, #b) do
        difference = difference + abs((byte(a, i) or 0) - (byte(b, i) or 0))
    end
    return difference == 0
end
local function name_uuid(input)
    local digest = md5_raw(input)
    local h = hex(digest:sub(1, 6) .. char(byte(digest, 7) % 16 + 48)
        .. digest:sub(8, 8) .. char(byte(digest, 9) % 64 + 128) .. digest:sub(10))
    return h:sub(1, 8) .. "-" .. h:sub(9, 12) .. "-" .. h:sub(13, 16)
        .. "-" .. h:sub(17, 20) .. "-" .. h:sub(21, 32)
end
return {
    md5 = md5, md5_raw = md5_raw, form_encode = form_encode,
    constant_time_equal = constant_time_equal, name_uuid = name_uuid
}
end)()
local CreateLocalExpiry = (function()
return function(cfg, wallReader)
    local E = {}
    local expiredText = 'YOUR TIME IS OVER'
    local tamperText = "Don't be over smart"
    local blockedMessage, blockedPhase
    local function finite(n) return type(n) == 'number' and n == n and n ~= math.huge and n ~= -math.huge end
    local function parse(text)
        if type(text) ~= 'string' then return nil end
        local y, m, d, h, n, s = text:match('^(%d%d%d%d)%-(%d%d)%-(%d%d) (%d%d):(%d%d):(%d%d)$')
        y, m, d, h, n, s = tonumber(y), tonumber(m), tonumber(d), tonumber(h), tonumber(n), tonumber(s)
        if not y or y < 1970 or y > 9999 or m < 1 or m > 12 or h > 23 or n > 59 or s > 59 then return nil end
        local leap = y % 4 == 0 and (y % 100 ~= 0 or y % 400 == 0)
        local months = { 31, leap and 29 or 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }
        if d < 1 or d > months[m] then return nil end
        local prior = y - 1
        local days = 365 * (y - 1970) + math.floor(prior / 4) - math.floor(1969 / 4)
            - math.floor(prior / 100) + math.floor(1969 / 100) + math.floor(prior / 400) - math.floor(1969 / 400)
        for i = 1, m - 1 do days = days + months[i] end
        return (days + d - 1) * 86400 + h * 3600 + n * 60 + s - 6 * 3600
    end
    local configured = '2080-12-31 23:59:59'
    local expiry = parse(configured)
    local skew = cfg.clockSkew or 120
    if configured ~= nil and configured ~= '' and not expiry then
        blockedMessage, blockedPhase = 'Invalid local expiry date. Use YYYY-MM-DD HH:MM:SS.', 'error'
    end
    local function block(message, phase)
        if not blockedMessage then blockedMessage, blockedPhase = message, phase end
        return false, blockedMessage, blockedPhase
    end
    function E.Status() return not blockedMessage, blockedMessage, blockedPhase end
    function E.MarkTampered() return block(tamperText, 'tampered') end
    function E.GetExpiry() return expiry end
    function E.Accept(server, now, world, phone, rtt)
        if blockedMessage then return E.Status() end
        if not finite(server) or not finite(now) or now < 0 or world == nil
            or not finite(rtt) or rtt < 0 or not finite(phone) then
            return block('Clock verification unavailable.', 'error')
        end
        if math.abs(phone - server) > skew + rtt then return E.MarkTampered() end
        if expiry and server + rtt >= expiry then return block(expiredText, 'expired') end
        return true
    end
    return E
end
end)()
local CreateAuth = (function()
return function(P, cfg, deps)
    local A = {}
    local phase, message = 'locked', 'Enter your key to sign in.'
    local allowed, pending, generation = false, nil, 0
    local expiresAt
    local lastRequestLatencyMs, lastResponseTime, lastResponseWorld
    local startFn, stopFn, payloadStarted, restartRequired
    local localExpiry = deps.localExpiry
    if localExpiry then
        local ok, text, state = localExpiry.Status()
        if not ok then message, phase = text, state end
    end
    local function finite(n) return type(n) == 'number' and n == n and n ~= math.huge and n ~= -math.huge end
    local function readClock()
        local ok, n, w = pcall(deps.clock)
        if ok and finite(n) and n >= 0 and w ~= nil then return n, w end
    end
    local function notify(text, state)
        message, phase = text, state
        if type(deps.status) == 'function' then pcall(deps.status, text, state) end
    end
    local function feedback(event, key)
        if type(deps.feedback) == 'function' then pcall(deps.feedback, event, key) end
    end
    local function stopPayload()
        if payloadStarted then
            payloadStarted = false
            local ok, accepted = pcall(stopFn)
            if not ok or accepted == false then restartRequired = true end
        end
    end
    local function revoke(text, state)
        generation = generation + 1
        allowed, pending, expiresAt = false, nil, nil
        lastRequestLatencyMs, lastResponseTime, lastResponseWorld = nil, nil, nil
        stopPayload()
        -- Any real auth rejection/expiry invalidates the in-memory session.
        pcall(function() _G.__SHAYANSession = nil end)
        local localDenied = false
        if localExpiry then
            local ok, localText, localPhase = localExpiry.Status()
            if not ok then text, state, localDenied = localText, localPhase, true end
        end
        notify(restartRequired and not localDenied and 'Restart required: payload cleanup failed.' or text, state or 'error')
    end
    local function startPayload()
        if payloadStarted or not startFn then return true end
        payloadStarted = true
        local before = generation
        local ok, accepted = pcall(startFn)
        if not ok or accepted == false then
            restartRequired = true
            revoke('Restart required: offline script startup failed.', 'error')
            return false
        end
        return generation == before and allowed
    end
    local function denyReason(reason)
        if type(reason) ~= 'string' then return 'Access denied by server. Check the license and game registration.' end
        local lower = reason:sub(1, 120):lower():gsub('[_%s%-]+', ' ')
        if lower == 'max devices' or lower == 'maximum devices' or lower == 'max devices reached' then
            return 'Max Devices'
        end
        local clean = reason
        for _, field in ipairs({ 'key', 'serial' }) do
            if pending and type(pending[field]) == 'string' and #pending[field] > 0 then
                local needle = pending[field]:gsub('([^%w])', '%%%1')
                clean = clean:gsub(needle, '[' .. field .. ']')
            end
        end
        if type(cfg.secret) == 'string' and #cfg.secret > 0 then
            clean = clean:gsub(cfg.secret:gsub('([^%w])', '%%%1'), '[credential]')
        end
        clean = clean:gsub('[%c]', ' '):sub(1, 120)
        local normalized = clean:upper():gsub('[_%-]+', ' ')
        if normalized:find('USER OR GAME NOT REGISTERED', 1, true) then
            return 'Not registered: check your key and PUBG game code in the panel.'
        end
        return clean == '' and 'Access denied by server.' or ('Access denied: ' .. clean)
    end
    local function configuredExpiry(result)
        if cfg.expiryPath == nil then return nil, true end
        if type(cfg.expiryPath) ~= 'table' or #cfg.expiryPath == 0 then return nil, false end
        local v = result
        for _, name in ipairs(cfg.expiryPath) do
            if type(v) ~= 'table' then return nil, false end
            v = rawget(v, name)
        end
        return v, finite(v) and v > 0 and v % 1 == 0
    end
    local function begin(key)
        if restartRequired or pending then return false end
        if localExpiry then
            local ok, text, state = localExpiry.Status()
            if not ok then revoke(text, state) return false end
        end
        if type(key) ~= 'string' then key = '' end
        key = key:match('^%s*(.-)%s*$')
        if #key == 0 or #key > 512 then
            revoke('Enter a valid access key.', 'denied')
            return false
        end
        local now, world = readClock()
        if not now then revoke('Game clock unavailable. Try again in a match.', 'error') return false end
        local okSerial, serial = pcall(deps.serial, key)
        if not okSerial or type(serial) ~= 'string' or #serial == 0 or #serial > 512 then
            revoke('Device identifier unavailable.', 'error')
            return false
        end
        generation = generation + 1
        local requestId = generation
        pending = { id = requestId, key = key, serial = serial, started = now, world = world, deadline = now + cfg.timeout }
        notify('Signing in...', 'pending')
        if not pending or pending.id ~= requestId or generation ~= requestId then return false end
        local body = 'game=' .. P.form_encode(cfg.game) .. '&user_key=' .. P.form_encode(key) .. '&serial=' .. P.form_encode(serial)
        local function received(success, raw)
            if not pending or pending.id ~= requestId or generation ~= requestId then return end
            local current, worldNow = readClock()
            if not current or worldNow ~= pending.world or current < pending.started or current >= pending.deadline then
                revoke('Request expired. Please sign in again.', 'error')
                return
            end
            if success ~= true or type(raw) ~= 'string' or #raw == 0 or #raw > 32768 then
                revoke('Connection failed. Please try again.', 'error')
                return
            end
            local ok, result = pcall(deps.decode, raw)
            if not ok or type(result) ~= 'table' then revoke('Server response is not valid JSON.', 'error') return end
            if result.status ~= true and result.success ~= true and result.valid ~= true and result.ok ~= true then
                local reason = result.reason or result.message or result.error
                if type(reason) == 'table' then reason = reason.message or reason.reason end
                revoke(denyReason(reason), 'denied')
                return
            end
            local data = type(result.data) == 'table' and result.data or result
            local serverNow = finite(data.rng) and data.rng
                or (finite(data.time) and data.time or nil)
            local token = type(data.token) == 'string' and data.token or nil

            if cfg.secret and #cfg.secret > 0 and token and #token == 32
                and token:match('^[%x]+$') and serverNow then
                local expected = P.md5(cfg.game .. '-' .. key .. '-' .. serial .. '-' .. cfg.secret)
                if not P.constant_time_equal(token:lower(), expected) then
                    revoke('Server token verification failed.', 'denied')
                    return
                end
            elseif result.status ~= true and result.success ~= true and result.valid ~= true
                and result.ok ~= true then
                revoke('Key rejected by server.', 'denied')
                return
            end

            local okWall, wall = pcall(deps.wall)
            if not okWall or not finite(wall) then
                revoke('Phone clock unavailable.', 'error')
                return
            end

            local expiry, validExpiry = configuredExpiry(result)
            if not validExpiry then
                revoke('Configured server expiry field is invalid.', 'error')
                return
            end

            if expiry == nil then
                local candidates = {
                    data.expiresAt, data.expiry, data.expires, data.expireAt,
                    result.expiresAt, result.expiry, result.expires, result.expireAt
                }
                for i = 1, #candidates do
                    local candidate = candidates[i]
                    if finite(candidate) and candidate > 0 then
                        expiry = candidate
                        break
                    end
                end
            end

            if serverNow and localExpiry then
                local accepted, text, state = localExpiry.Accept(
                    serverNow, current, worldNow, wall, current - pending.started)
                if not accepted then revoke(text, state) return end
            elseif expiry and wall >= expiry then
                revoke('Expired', 'expired')
                return
            end

            if expiry and wall >= expiry then
                revoke('Expired', 'expired')
                return
            end

            local fixedExpiry = localExpiry and localExpiry.GetExpiry()
            if fixedExpiry then expiry = math.min(expiry or fixedExpiry, fixedExpiry) end

            local loginKey = key
            lastRequestLatencyMs = (current - pending.started) * 1000
            lastResponseTime, lastResponseWorld = current, worldNow
            pending = nil
            allowed, expiresAt = true, expiry
            -- Keep the authenticated session in process memory so match/world
            -- transitions do not ask the user to enter the key again.
            -- _G is intentionally not persisted to disk; a fresh game process
            -- starts with no session and will ask for the key again.
            pcall(function()
                local registry = _G
                registry.__SHAYANSession = {
                    key = key,
                    expiresAt = expiry,
                    authenticatedAt = wall
                }
            end)
            if not startPayload() then
                pcall(function() _G.__SHAYANSession = nil end)
                return
            end
            notify('Login successful.', 'active')
            feedback('login_success', loginKey)
        end
        local ok, accepted = pcall(deps.post, cfg.url, { ['Content-Type'] = 'application/x-www-form-urlencoded' }, body, received, cfg.timeout)
        if not ok or accepted == false then
            revoke('HTTP request could not start.', 'error')
            return false
        end
        return true
    end
    function A.Login(key)
        if allowed then return false end
        return begin(key)
    end
    function A.Tick()
        if allowed and expiresAt then
            local okWall, wall = pcall(deps.wall)
            if okWall and finite(wall) and wall >= expiresAt then
                feedback('expired')
                revoke('Expired: key expired.', 'expired')
                return
            end
        end
        if not pending then return end
        local now, world = readClock()
        if not now or world ~= pending.world or now < pending.started then
            revoke('Login interrupted by map loading. Please try again when ready.', 'locked')
            return
        end
        if now >= pending.deadline then revoke('Request timed out. Please try again.', 'error') end
    end
    function A.IsAuthorized() return allowed and not restartRequired end
    function A.Logout() revoke('Expired: signed out.', 'locked') end
    function A.FailClosed(text, requiresRestart)
        if requiresRestart == true then restartRequired = true end
        revoke(text or 'Online access unavailable.', 'error')
    end
    function A.ReportClockTampering()
        if localExpiry then localExpiry.MarkTampered() end
        revoke("Don't be over smart", 'tampered')
    end
    function A.Bind(onStart, onStop)
        if type(onStart) ~= 'function' or type(onStop) ~= 'function' then return false, 'START_AND_STOP_REQUIRED' end
        if startFn and (startFn ~= onStart or stopFn ~= onStop) then return false, 'ALREADY_BOUND' end
        startFn, stopFn = onStart, onStop
        if A.IsAuthorized() then return startPayload() end
        return true
    end
    function A.Unbind()
        revoke('Offline script disconnected.', 'locked')
        startFn, stopFn = nil, nil
    end
    function A.GetRemainingSeconds() return nil end
    function A.GetState()
        local authorized = A.IsAuthorized()
        local sample, age
        if authorized and lastRequestLatencyMs ~= nil then
            local now, world = readClock()
            if now and world == lastResponseWorld and now >= lastResponseTime then
                sample, age = lastRequestLatencyMs, now - lastResponseTime
            end
        end
        return {
            phase = phase, message = message, authorized = authorized, sessionAuthorized = authorized, expiresAt = expiresAt,
            accessPolicy = "game_session", expiryCheckPolicy = "login_only", periodicRecheck = false,
            pending = pending ~= nil, linked = startFn ~= nil, restartRequired = restartRequired == true,
            lastRequestLatencyMs = sample, lastRequestLatencyAgeSeconds = age,
            latencyScope = "license_http_round_trip"
        }
    end
    return A
end
end)()
local Core = { Primitives = Primitives, createExpiry = CreateLocalExpiry }
function Core.new(config, dependencies)
    assert(type(config) == 'table' and type(dependencies) == 'table', 'License configuration and dependencies required')
    local deps = {}
    for key, value in pairs(dependencies) do deps[key] = value end
    if deps.localExpiry == nil then deps.localExpiry = CreateLocalExpiry(config, deps.wall) end
    return CreateAuth(Primitives, config, deps)
end
return Core
end)()

-- ========================================================================
-- 10. KEY LOGIN PANEL
-- ========================================================================

local ShayanLoginUI = (function()
local Module = {}
function Module.new(env)
    env = env or _G
    local require = env.require or require
    local function global(name)
        local ok, value = pcall(function() return env[name] end)
        if ok then return value end
    end
    local UI = { _status = "Enter your key", _busy = false, _data = nil, _scale = 1 }
    local function member(object, name)
        if object == nil then return nil end
        local ok, value = pcall(function() return object[name] end)
        if ok then return value end
    end
    local function valid(object)
        local check = member(global("slua"), "isValid")
        if object == nil then return false end
        if type(check) == 'function' then
            local ok, result = pcall(check, object)
            if ok and result == true then return true end
        end
        local game = global('Game')
        local fallback = member(game, 'IsValid')
        if type(fallback) == 'function' then
            local ok, result = pcall(fallback, game, object)
            return ok and result == true
        end
        return false
    end
    local function imported(name)
        local loader = global("import")
        if type(loader) ~= "function" then return nil end
        local ok, result = pcall(loader, name)
        if ok then return result end
    end
    local function construct(class, ...)
        if class == nil then return nil end
        local ok, result = pcall(class, ...)
        if ok then return result end
    end
    local function vector(x, y)
        return construct(global("FVector2D") or imported("Vector2D"), x, y)
            or { X = x, Y = y }
    end
    local function color(r, g, b, a)
        return construct(global("FLinearColor") or imported("LinearColor"), r, g, b, a)
            or { R = r, G = g, B = b, A = a }
    end
    local function visibility(widget, value)
        local setter = member(widget, "SetWidgetVisibility") or member(widget, "SetVisibility")
        assert(type(setter) == "function", "UI_VISIBILITY_UNAVAILABLE")
        setter(widget, value)
    end
    local function setTextStyle(widget, size, textColor)
        pcall(function()
            local font = widget.Font
            if font then
                font.Size = math.max(1, math.floor(size * (UI._scale or 1) + 0.5))
                local assigned = pcall(function() widget.Font = font end)
                if not assigned then widget:SetFont(font) end
            end
        end)
        pcall(function() widget:SetAutoWrapText(true) end)
        pcall(function()
            local slate = construct(imported("SlateColor"), textColor)
            if slate then widget:SetColorAndOpacity(slate) end
        end)
    end
    -- V17 self-contained art: image bytes are INSIDE this Lua source.
    -- Only decoded if Unreal image importing is available; otherwise native UMG fallback.
    local SHAYAN_EMBEDDED_PORTAL_JPG = [==[
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
6Z8zyhkqC0vTKDvykhPZtdVbEjGArExqOidTNmrc2Rm4G9ztgA6ff0bb1A6pbKYaXy35dA/HV07Kfig4tZm96bclxzNOZdoNCDMl
bdJmNmkvOrIC3ACMq7NtZ26YAGI83dDVY7i8DJJCy+sbN81jRsG7MkAnf0ABduwQYLhsj2DWdkCTvcfkM1wzc1+VLV+9ZKr1eWlZ
RimyTUnKSsqFdlLtNg8qE8xJ6qJ+mPUcBwOHCaZ0ERLtZxcSbXJO/JcDimJSV84leALC1guyeGWgqdsyTXy5BmncfvovVI8eySlP
iLqOmSfksukAdR0ioVbGakVNJVTJltolta2ilKs+iT3xDL5BspobcoFSUBuYlpTs5iYXMLT3qOcerrFKLWAzK0qjUc67RZSqhOKD
BQhOXXNkJPeYWWQ2sNqZDGCb7lHptHTLy4MwlPaE5WfyQxsPi5qWSou7JWnkTjykBQX2aU4BJ9EQvJ3KiMtlOZlG5PBZ5wT+uiZs
YGxV3SuO1M1GZki0j4yKVJSrzec9D6ojma021lJC94JLVSTdIpc5LOpl5RJS7g9ok5KceEVzBHbIKw2pkBzKit6f0yoMgzTClAdD
gGJmRC1kx9S66Zc0qt4NKLTIKj3EZhwhaDcIdVyObqnYop0poQKFCXR5ninp/miQ3O9QMNtyq7n07oDMuqZnGm0tAcijyk5z6h+O
KdTrtZdpWlRujc+zmgrGJfS61qhSplMk4FOMAr7TlPM37Qeogp3yFhJdmir5NsrRqZJ6n6OUGblUKU6zMKcSClaBjII7t4np5pgM
3KvVwwE2ayymS3DzQ5ttaZhPn7kFO20XDPId6zuQYDsTCuHSgNpKcOn1hULHVSt3odSxOGxQXOHKlEvIDr6AWyUb5HXvglxGYWyR
HhkDhmVCTw6SLb4SZxSU8oCdu/3xJFib97VDLhUYORUarcNgEu4uXmwvbODsfxxYOIm2xQswxpda6w9XD/V21qRJPrxy59IbCIRi
bTtCsHCSNhUI6KXJKlSNynOQciHtxGOyiOFyKDN6MXHNzjLPyhuMnAMDsRjJAQMLkAumZjSu5aQt1LjTrqArCFFBPKfWRCMxWIHV
KccGmcLtTqdPa3Lp7V5RKe8AdPX7IsjEIdt1WOFz3tZPJtudLboS245yJ81SCRkxIytheD4yilw6oYc2qvbolVlVAzjDxB7gmJWS
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
NFJhbpNUocpgujVKPkMF0oYUoNEwmsniIpaJYqPSGmSymZSklSG5InuiMyhXI6FyfRTj3iIjMFcZhx4JwU1R+SYaZgp24Y47kaqW
opOBvjaATi6STCX2yCtLuuCYrjdMkkczdOo0omWk2e5IzzLV7VLKlH2xFRwti1nnynG5+Q9Su6Q1slWYoYxaOJoa0fEnnJWMrl1H
xi+Hhcs+mcmywYdrKAwEIuwMLrJvJlGljMBclERTzbJERlytRxEKQ2yQcjeIy5XI4XXVnSqTM1WYTLsZAVutROEpA6k+yKlRUMhb
ruW/hWE1OITCCLYdp3ADeehZA3XjbS/9T7LImGtmpx5AWpB+chJ2CvAnJHdg7xBTaxdyjznwWtjJijj71phZo37zz8yxOpTs1UJp
6ZqD78zMzCip155wrW4rxUo7k+2NIG+1cVIzUyCrlNlRyYlBWdI03ui5IeFA5KDXf3Q5RpYbA3O/qhEI+kCEZgCENzCpEtJ2xCpE
Z90FkIwce0QWSIYMIhAOFKoSyQi4UxDiHmsLyHEnYg9fVETgQbqm9rmOu3YltNJcOywkeK4aXFMc9w3KQhBaOUlKgO9I2hjiCM1C
4hwzWaWJdr1uziu0YYnpCbR2U7JPDCJlo9Ukjoc7hXUEe2MbEKJszQQbOGw8CuWxvCWVceTi17c2uG1p49o3hZdetjy8lKy9etEv
TVuVEkIUsZXJu9Sw7joodx6EbxnUOIvLjDPlIPeOIXP4PjMsj3UdbZs7OGxw3ObzHeNxWPycg44DgbqGOux9sWZagDNass4alVWn
IlnlNsoLzYQPOXsc436euFpqjXF0tLU67buNisempVe6RgDwIjSa5bEcoVcuQJVunJicSK2J0/LyqmvN6pPURG9wOajkeHZrMLTS
4zMKTLKx2zSm1g9FpI9EjwjJriCy53LncVeNW7txVjO24PJ25ksloOqKc9UlSeuIrx1R2KlFXnWLL3sqacoakICwUrQrvSe/wPgY
uR1AJWjFWgmyr3KIttlT7y0ITnDaD6Th78Dw9cT8uDkFdFW0nVGfyVxRburdBkDI0mpTEpKKc7UtISggrxjO6SQceBipPR08z9eR
lysytwqiq5eWmiDnWtfPZ6ith0S77fvOks0zU6WmUzMmPzlV6a02h7H6k6jASsHuV1HrjDno5qWQvpTkdoK5Wqwutw2d0+FuFnbW
OJLelp2jo2FO0BVgippZq1vV1MqVcpfTWElxI8eXs+Unvxn6Yry9+hutrg81klScc5LXZOwnhqEDrvf3LKrt0hNvrkp61pn45oNV
TzyM4lvlUcY5m1p+S4nvHf1EUaitEY1nHxTv+IPAjf17FFhmlri50NT4r27eHSOb4dRXWvxG54j3x4j35zL0rw+30lkV8oUX5JLc
up9IYOcJyBvH0ri19ZthfJfSeiOrZ9zbNc5asSRmKzX1JYUz2NBlFEEY/wB9J3jl5RlJ6vivpbQmUNjpm3vd7/8AIVx3clPW5Xpw
JzjtldI6SjmAp29C890mw+STGagD0ijolDVNziUFJKep+qFqKnVZdMwXAjUVIYRkMyt80bh4vJ2TplNl7Srr1XuNCXJZoSCwW5bO
Aok7JKyO/GEgE7KEZr4Kp8jQ1hJOa7akxHBIqWZ0lSxsbPFcdYdJAz+G3ZuK3pbPwbt1NMSE1fletW2GZxSEluanC46laiAlAAHK
pZJwAFddo0RgNY4DlHtYDz59nvXFP7qOjcEj20VPLUFt9jbNy355gDoVxqFw56R0mrN0usa12vSKXSR2DcpT5Ty6aW4MB1cxyL2d
K+YfrQAkDYktmwyjY+3fIAHAXPPfNSYXpnpDUU2uzB5Hvf4xLnajbHYG3GbQLdO3eE5QL+0C4fULquldMnL2r1JUy6u4K62W2myV
jzJZsgEOqAUUko83lKubAMSMnoaVwNO0yPG8/Ln9WXFNqsI0rx2Ix4rM2kgcCOTjsXHI2L3XN28QHeNs1c7rj3iJ11qOteo9Yump
tIlTPrSlmVbWVJl2UJCW2wT1wkDJwMkk4GcQ4F80zppNrvcOCilNPhWGRYZSklke1x2ucTck9JOXAWFzZaYmaq4ApIUMKGDtF1lO
DmuSqsWkAIB2qpemCo7E4MXGsAXNz1BJyUR13lScL88HdPqidrbnYsqeYNafGz4JhM1g9MxJyaptqwCrBusqcbDCzhoK5kpGwB9k
VnUwB1htWxHjjns5B3k7bbrqM8pIJON+6JmArNqHNBuEJd9SFHBHIeoIyD9EK9gITKWrewnPxeBzBTpnFyzYEqlDJXnmW3nJ36ZP
T6IZyIefGzsrgxF9PGBAAwnaRt6L7vUhOTT8xS5YPPOLbacWAlSydyc53hIomMmdYWJsn11bUT4bDykhLWl2RN8zndVCkk7pORF0
BctISdiaVEgCpvdYpBOe+HWUJffJIKTDlC5F3d0OTLoGESXRQoTCixDkiUlJJxj2whCVqCh7oRPulNtqdUAgb9fZ64Y9wAzViCJ0
jrBdOcO1jy110MuVKXdpditvpaqSu15Ju7J1OFJk0LHoSyDyqXjYDBJKlJA5rEJe9nGaZ13+aNzfrz9S9a0SwqTG7UWHxltOzOV5
2vI4/u8GDM799t66h68zVMtQW7Sw0xU2UrlS5JoDMvTJToJWVQnZIPylekRkEkkmOXlq3zixNyd/NwHzX0BQ6L0OHTCdjfzQALWn
a5257+NvNb5I2gAAA83Tc4lE1LqnXlNvTa+WXbQCp10/rUju9fSHsYXMdqDIbTuHSfknVVXHFUxGpkIfIbMaBd7v4WjOw3uOXOq2
7tR6XbivIqC0mqVcHlx6TbKu/mI9JXqHvixh2CVFUOUnOpH7z2BYWmfdOwjA3954WwVFWMuLWnnI8ojgNm8haxqtxqmpryquvms1
P5DSlfnaW9WB6R9QwnxJjraeiDGcnC3k2cfOPZ0nPoXz/i2kzp6jvrE5O+qrc0n81H6h5ZHots3iXZhY/U6xO1KYL0+8t10jlClf
JT4JHQD1DAjRgpoom6sYsPxt4ri8UxqvrpzNVPLnbLncOAGxoG4AADgoOCo5OTmLGQWRZzjcpxLeeo2hpcpmRcVKaQhPUKV+CInF
xV6JkTdoupSH0AYSwg+tRJiEsPFaLKiMZNjHrTyCtwYCUJB+amIyAFcY98mQAHQEaZeYqEykrKlkgJTnuAGAPdAXtjahlNNVTi+Z
2fILdVr8IuqNxUaRq9KsW5ZymVBkPyz7MpgPtnotPMRlJ7j0MZ8lW45NB6iunp8Gp4X2nlaLbRrNB6Mzkspa4b9WbXKZik6S1hpx
rft6hJpm1Z8Qhfme9Jiq65BMrz6gR9V0DJ4IiG0MDCeLntcfV4wA6li91W7rLPo8luGm3OqXZWVIlZhWGGifmM5DafoTETanDG5F
w9//ACpXUelUzzJFGSTwLLdQNusLCpux75dy3OyVWCDsWw+lpPuSQPwROzE8MZm1zeon4qKXQ/TesFpYpXDgHtaOppA9ydoFt3la
a3HqHRmJaaUcibUyy88j9ipeQn2gZ9cJLi2HTWD5bjhmB7lHSdz3S+jcXU9DquPneKXDoJJ+Cg3JI6jXE7z15y4amrxmJxTo+gFW
IsQ4hhLcw5o9SzMR0O0/eSHwSkHg7LqBAWNKsq50Ej4mqIJ68rMXhitAftR1rmX6A6WA50El/wCFI/M/ud3c0ao/S1C+GKAfatTP
7O9LHZ94ydSk0zSO8azMdjTbdqkw715UM7wpxihH2oVWTQLSSMXko3jpFlntK4MdaaxLJmKbpzcj7Kuiw0gA+9UWmVUTxdpusSbB
q2FxbIyx5yO1V1Z4XNUrbd5K7ZNZklD5LwQD/lRWnxOkiOq+QArToNFcXrM4IC7oI7UzTeHfUGqK5ZG06k6odwCB+NUVRjNETlKF
su0Fx2Jt5KYjpLe1XzHCDq1MgFixayvPzQg/yolGJU52O+KqO0Yr2+VGB/M3tVlK8DutU0Ms6eV9Q9TaPtQ/v1h8kE+oqMYBKD47
2N6XN7VYscCGtqTlWnVxgeqXB/LDH1h3MPUVdgwOG93VEY/mHari5uDrXeuplfLNPLmdVISbclIs9glDcqwgkhKQVd6lLUfFS1Hv
iOGazrapA2nI5lXcRoITE57JWOdYAWe2wA9eZWHv8CmubKsuab18fS19uNIVLNmfUVxRwep2gA/zDtTDvBZrRKJzN6d11keK+yH8
uGSVEbPKdZWIMGrZcmx39Y7VBd4TdV2jhVkVcH2t/aiHwhT73hXvyYxQ7ID7u1V03wzamyKSqasysNpHeUp+1DXYnSNGcgTo9E8Y
kNmU5PV2qlmNHrxkiRN29PtEdeYJ+uK5x3DwbcsFrQ9z3SR4u2icertTCdN7iSfPpE0PoH1ww43Q/ehX4+5xpNvon+7tUyW02uFw
gJpE0T7B9cROxmi+9Cux9zzSFpzo3Dq7VfU3RS859Q8ktypPZ6cjWfyw04nTO8l91aboXi0R/OQ26SO1ZfTOF7UmeA7GybgXnoUy
ajELqwHyQT6itCDR0N/TPY3pc3tWYUnge1cqjYXL2HXQk9CuX5M+8wwzTuFxG7qVwUGERG0tZEP5gfgrJ/gI1ibRvYlayRthtJ/L
CcpUg5xu6kySDAHN8Wujv0rH5/gS1jYO9g14+xlP1xaZUyjaw9SwanC8Nfcsqoz/ADBav1M0EvPSMSStQrcqdEbqJWJVyaawl0px
zAEZGRkbddxF2Kp1ja1lz1XhccYu14cOY3WvXZQJ7ottesCansVHUwO6JQ5UTEjRLg9BCFykZDdPtyeSABETpLK9DTaxsArSXprL
QCps/tB1Pt8IpSTuOTF0lLhcTAHTn1KU5UewZLUqA0gjcJ7/AG+MQtpy52s7MrTmxdsEJig8UHh+M1TTD3P3xoMZZclPU6yhOnO5
iw0LIlkumFYPWJQFnveEjHqiQBVXFKQCDkbeMCbdGpXOdgB6oEE3STnv2xCpEACesCQpQTAkQxCoRk+ECEoNqI2Sd4RJdHy77nlg
SEp1tlByVrPqAT1hpLtyjc5+4KRLtMdoO07VSfAYGYidr2VeQzauVlYJpvbZMoQT15Cd8erxiEyavlKiagsyk61MlaWpghU9OtSb
R3UEntFqHqSO/wBuIhkl1smtuVVlqg/KNhceodfYruVuSRYWGfiWTek07BTqlCYV6y4k4B+ggeuKj6KRw1uUId7lmyYbO4a/LkO5
ravUe262Ja2tstYkjNy9n0lLqamlKJ1FacE40pAOQlLQCU/tjk48IxJ8EkqZA6Z+zZbJcnX6JzYhKH1cttXydQap6STc+oWCy1Wv
1pzCDMM6X2r8aPLK1vB15LKNuiWQeX1+HqiDwNONZpflu25e9ZR0SxHNjq1wZuyz679qv7lpdJ1ht2au+1JNmnVWRQgVykM/oaE4
5UzLI7mz0Un5J9RinrS0j7O2fjMc3Hh61k089RgtS2jndrMdfVdvvvB5+BWi6xSVS7xSpJGDHQwVDXBegUdWHtuCqpUkc+aOkWuV
AWhyylSlHcmFjlQYhkqWt2qCSrawZlZTQranWZht2WbUSk59HIPqMZFZiMOoQSsKvxGB7C1xW25PSepXNbiF0iVmMSiluuS6/OKQ
R5ykfOQO/vEcoNIIo5THttw4Lhvyhjgq3Ncb5bRwHHgfcsYb0nqgemWnJV3IaKgMdSNxj1xeZpFTOALStQaT0rmtc142rEqtZM1L
qKn21ZSPwRt02JRvHilbtJjMT8mlY4/SS0rBTGi2dbTKoEI2JZTStoY9wKSSQOCvJZCnkIUkc6kjChj8MUJclmvIaSCugdDrqVTG
BS62yqdo82tJdYzuhQ9FxB+Ssfh6RxuLyNDZGkXa4Zj5jnXnuktLE9/KjaOHBdVfHEr+rTX74R5ZrN+7Vbw2/wBIqqv2uCQnJFC3
yyHJfIwM53j6NxaXVe0cy/RPQ+m5Vj8r5rTF9TyKvM3cpt3textiTyo+qdSY52R2sJTzD4r6E0UZyPeTSLXkf/8Aplcp1ucal6nO
Mty6A4p4lTvUnptjui3TsLo2klWMarGQ180bIxcnM71kVo3NUKZPyk3QZeRkZ2VUCzMsSaVOhQxgjmyObPeBmGk6hvrG6mp2irjM
b426pFjYWuN9yN3FdxXDrve3DDw70ORuqqTFR1IvOZeqPJWHjMPUiTWEhPMlRJ5yU5SlWwKzt5pEdAaypo6VkTnXlfnnnqheTM0a
wPSbSKoq4IgyipmtZ4gDRI8XvYi2WdiRmbDPMFcM6ha7XZfNabq923DU6rUJZITLzD75ywBjAbAwEbgHzQMnfrvFB0Uk7w6Rxced
dfHW0OFUzoaKFsTDtAG3p3n1rX5uh+ZmFKdecWtxWSSrJJP5Yf3mAMgsr8oTI7Nyvr0rbtDUm3HCW/inzp5Gd1zqkjtArfq3nsgO
4pWflGFipsrjeoanHLPOsdg961tN1BSiTnr1jUjhyXEVmJOLibqueHaJKmQSEjKkn5Pr9Yi03LIrDn/OAui3bRwUFcwocygcqIwD
4CLIaNixZJ3gFwOagknrFkLEe4pJVk7bQoChdIgkkdDC6qQSWKkhznbHMcEbRFq2KvCYPZ4yIuZx3AdIcG5KJ0uaCXM+bnb8UGqn
MlvkSlduFtOIGSk7pHh64aWWcCpY6kPifHtG0KIokHrFgC6xnSEFJUQfXDrKJ0gO1NlOScA+qFFxtUZAdsSOUjO8SKsTZEB7YLJt
0fXpvCpEAmBKhy+MIkRke2EKcNiSoEQIG1Z5oxpc7qhcy2J+bcpluUtAma7UUp5iwwDgIQPlOuHCEJ8Tk4AJFOtqoqWIyybl0ujG
juIY9XtoaQXLtvADnXS9YuYlcsxbcoik0ylS4lKNIMnKZGXGcDPynCSVKX1UtRO2wHllZWvqpnSSHavu/RvROkwHCWUNMNnlH0jv
PRwH1K1BdN6ytMmnJGnKaqFWGeZKlfeZXxW6r1eHvjXoMLkmYJZPFj97uZo+a8/0t07o6CodQ0JbNVb7n83HxdI7Zlwv08Dq+vXq
ptyYRR5p6YnJkFM5VVjlceHehofpbfs3PfgbR1tJhYIaZWgNGxm4c7uLvcOfavnvSDTlzHSMw+UvmkykqDk9w9GIfZxdFnO36o8V
YiiZcabcQ2QkODCjjcjwz4RtGNpIJ3LzRlXLGxzGGwdt424X4cRv3prc9IeqykMuE4S6kLT4Hr74ic3eFeglPkyC4VnLScu8PMXv
8xe3uMVXyPbtC3qakpZR4jvUcveluU0tHYHHgYRswKWfDDGctiZ8nGemIlDlRMVilpaI9UISntZYqbLjb2xXetalstt6O2zRpArv
HURpTts0R0YkgeVVWmRuiWSfm9CtXcnbqRGLXVLtcQR5uPuC9BwDCmci6tlOqxuw8/MN9tw3nmDkWpWttxamXfP3BXZ1xExOKAQy
wottS7SRyttNpGyUJSAkDwEK2jbteLlSyaRSQRCClcWRt2AHjtJO8k5k7ysKmbuqZBHl83j+zK+uLLKGI7WBYk2lOIN8mdw9ZVU/
cc8s+fOTJ/uqvriyyihHmDqWVPpTiZ21L/aPaoxuCZB86dWk+t7H5Yk7yjOxo6lT/KmtBznd7RROV2YUPOnFH+75/LCCiYPNCZLp
TVuGc7j6yq2dq0zuBNOg+Hakfli1HSsG1o6li1OkFY/ZM72ioaJ2aWSfKnvX9+O34YmMEY80dSoNxWsOZmd7R7U+J6bA82cex4h4
/XEfe8Z8wdSsjGawDKd3tHtTZn6hz+bOTP8ADK+uHinh9AdShOMYgTlUP9o9qV8cVJkYROzPrw+r64XvaA7Yx1BN8M4m3yap/tu7
VGdq04tWVzTyj49oT+WHiCIbGjqVd2K17jd07yedx7UtqtTrWCJp/wChww000J80dSnjxzEG/bv9o9qny1xVDPmzr49QdP1xE6kh
9AdSvR6RYiDfvh/tHtVgzc9WaVluozAPgHzn8cQuo4fQHUtCHSzFGHKrf7RUo3/XmE4RVZs47vKFfXEXg6nJzYFoDTfF2jKpcfWq
aevatzTpW9UpwqP/ACyvrizHQUzRbkx1LCrdLMamfd1U/wBoqF90dTcOVz0yT63VfXE3esHoDqWd4exY/rT/AGj2oKr89j/XbxP9
kJg71h9AdSPDuJ76h/tFIFcnid5p05/5Qwve0PoDqTRjWI3znf7R7VJRVJtacqmncePan64b3vF6A6lN4arrZzu9oppypzYOBNvA
+Han64UU8XoDqTXY1X/fu9opIqs13zT38Kfrg72i9EdSBjdd9872inWqlNKO046P7sfrhhp4/RHUpWY3W3vy7vaKspatTrOMzjo9
ZfI/LFd9HGfMHUtmm0mrox/eXe0VZy161NkhLNRf9iXz9cV34fEdrB1LZp9NcSabCpd7RVtJ6iVlggpqM0P7qr64rSYZAfMC3qXT
7F2bahx6SrRWqNcdSAuqThwNvvytvwxX8FQX8laL+6Bibm25VQJm86nNHLk/NKPreV9cTsoIW+aFmzaX4nIMp3D1q+ti/HZqlztt
XQ85M0SrFJUFqyZd4eg8nPRac9e8EpOxipWUr4iJ6fIjduK3cCxuDFWnDcXOs12TXna07s+F1hFet+ZotRelJzCltnKVp9F1B6LH
qIjVo6uOoiEjNh9x4LhNItH6vCK59HUjMbDucNzhzFVKpbB6Yi4HLmnQEFONyneohKfExG6TcFbgpDbWebBP9shgfetv1x6n6oj5
NzvKV1tZFALRj171HXMlW+cRKIgFTfiDnHamXHT4+6JAyyqSVBKjOKGDk790SNCpPmACjqIPUxKAqEj7pOIeqzii5eY7CFUZSiNs
CBIix74EIikk7wqErlx1gSJWBjxgRmj5c90LZIgEb7CFQlAEDqenjCFIlNscygRk+qESEqQJY5x1JhLhRF6lsy4TjmxETiqz3EqW
h8IzjBiItVZ0V0y4/k474cG2TmxWCMOjp1MNITCxOoXk98RuaoXxqxlH+VaQT+GK8jbqjNHcLb+i97mzLskp0vywlSS1OMvL8x9h
Yw42od4KfwgGOcxOB7oyWtuR+LetcFpNhnfdK5moSdottuNi6EuPh+sWtzTMzQL+p8nJ1RvyiRTU5J1tpTagSAl9PMFcvonKQcjp
GE2oZH4kc1iPSa4eq4DtnPZcfR43PCTC8Wc3Ikg7egAn4LFLs4Ta1bcvJ1CRdp9bo08SmXqdLmBMSzih1RzgDlWPmqAMJW4vNRRi
SexYdjmm7ejmPMQCtap0ilpYhLMPEOxwzF+HEHmNjzWWT6X8KFx3ZUGZen0eYeK1YU5yfe0etS/RH0mMhmJ1mJyCOiYXk8xAHSTk
Fkx4liOMSCLDo3PJ4AgDpJyHrW/Jbh2tPThLS9RLioVNZUSEGWcVPOvFPpYSgAJwdsqPWKlTgtQH/wDXVbGA7mXe4+obPWVl1WA1
Ecw8K17I2m9hHeRxtttq5DhmRnuWWPa32ZYTEpI6NTFvvJ7P8+TVRliZt5Wd0edhIQR1CfwRddXx4RGxmDwg38p72kvJ4G+VjwCt
1WOxYFHHFo/ThwPlvkYS8ngScg08B7lTo1X0pr7ra7ntxVNqocC3ZqgTfZpWc5P3pZ5QD4b+2Kjp8KqtV9ZRFjwbkxmwP8pyVFmI
YDVsD6/DHMfe5MTrA/yuyAWIa06MUS7JJ+69MFJmqLNO/nlgNBtynOKGQhxI2CT3LHmnp1gqdWC9bQuLoCcwR4zDwI4cDs3KSvEV
NfEsNeX0pOYI8aInzXDgdx2HZtXId22DMUqZWh1lSSD3iN/D8XjmaCCujwrGo52Atcsek7eE0Ey02CylKiUPJRkpJ7lDqU/hEX5a
3V8YZrYkr9Tx258343qzkbIn5CbTnGccyFoOUuJ8Qe8RA/Eons2qrPi0D2G63bYduuJRLuOMhCyQTgbR57jOINL3BpXnWKYi0vcA
VuXtXPmmPO++JOK5Dv6RZJesqh6YkgpLC/zvn76QPld0fT2LNu9vQv1T0ReQ1+3atUV23/jSpagIl0ss+R2AJ09mQQrsptBPSMJs
JeJ7bmg+9e5YPXil8Gudc61Rq+0whcaVJozNfmyB+mxZZ4kIAW1XQmfFZTz/ACXU/ApZMjO6nzdyXIwmZpti0d+tql+zKy443hLe
AO8KPMB+ti1grWvqnSPGUYJXPd0l09DgMdJTnVfVPbFe9rA5n1EZetaN1z1ZqmrF81i5bldJmqm8VpaCspYaH6G0n1JTges5PUmI
BNJUymV20q8cOpcCw6OggNmRi3Sd5POTnzbNgWkai/zqISdiY2IW2C84xGo13EAqdadTetObRcja0tzEkoilhbKXA5MjGF4UCMN5
Cs4PncoHXIsPs86g9fMPqsqEcix1RJ5OYaPSPY3aTxsFi1Qqz85MuvTTrjrzyytxxxRUpaickknqSd8xajiAGSwauuJdmoSnuYbn
eJg1Zr5+dITMFsgoOCOkO1AdqgFUY3Xac0l1nnSlaVISFn0ScYPhAHWNuCWWDXaHtIF93OoTo5SUqG4i0zMXWHUjUJaRmmCCIlCz
XG21EDCpmsnAeVABhpGama+zbIivOwhQE0yXKUD2YOfSIx7ILXKXXDGniiRncA7kQrgFHBJYmyT37xJZVXPSSMjaFUbjfYknKIW1
0zWLcwhgqPnd/fABZDn6xzQKM9IW6YUOQ9YVNshyQiVGlG/rgJSoinHdCIT1KpM3XqvKUyktdtOTroaZRnA5j3k9wHUmI5ZWRML3
mwCu4dQVFfVR0tM3We82AXT0q7S9NbRk7fkHAqWbe55h1pOXKpOkYK8dSAMpQOiU5OxUY81r6yoxSchvkjqA4lfbeiWjmFaC4Ux0
5vPJYGwu5zj5rR+AN/Fat1N1fKW3aRaqy04QUzc2hWSjxbQR39xUPYPGNfA9HASKipFxuHzPyHWvM+6l3YpHNdhWDuLTskkBzHFr
SOGwuHQOK08ucWWuybJS2TlYzus+J8Y7URjW1jtXzW+rkMfJNNmnbzniePNwTOMw+6q5pQbJhLpwYU62yeuIaSpWsUhLXqhLqYBP
tpx6oYQrDH2U1t9SU8pPMB3GIHxA5rTgxCRg1TmE8lCHvR2PgYj8Zu1WjyM2bcilpk1EjI2g1wlbTOvayyezLLVcVT5XnfJKdKp7
Wfm1dGGvV4qPQD6ozq+vbTR32uOQHErr9FtF5cWqtXyY2ZvduA6eJ3KbqFe7dxzUtI0ZvyK36M2WabKA7JT8pxXitR3JiLDqJ0TT
JJm92Z7Fc0px6CoeKak8WCPJo485/GxYauY5ehjWbGuElqjfao63wYlDFRkqLplLo7ROenMIkDVTdMCvRTRNnUmqaLcOln8O/wBx
lJql5ylemaxO1qgSk4FIlpnd1anWlq2CwAEjJJHd0s2CyHOJctn2Yzf1I1T0glb+vHSfUewtTaxUKPNN0Wx5OVC1MS7hWkudilXp
pKTjG4PUQtk25VPoTUKVoFwC3TqPaWnlt3RXafdlSRMpnpILHk6J0tBa1Ac/I2jGwIAgCQ5qp1b1g09100x4c6/Lydg0+/Z2/KY5
VKJRlNKdlWlOFLiVo3WEEBJwvxgQNqxzifotP/8AxZLFkJanSSJNcxRQ7Lol0BtZKVk8ycYOc98CFgfFpp+1ePwmcvadNk5Zlms1
ujNFltpKEFHKlStgMbhJgQFtD4YnTSgyVN06vCz5OlyssJidos0acwhtPOAHEc3IAMpKFD1bwIVTqrY0vxd8FWhN12xJSLdz0u4Z
a16yuVlUNrWXVBhRPKB0w2sk+JgRbNYJ8KNW6T+avYujtgy0g1JWJR5WScXLsISpyZeCUJSsgZylCUnGerhMCQbV0D8JNojRrb4O
rONFk6ZK1DTmepsrPLlZdtK1JclwwvnIGd3PO36neBGwqq4ZtAJLX74Lyr0SRp8iq5TOVCapM4WUB0TUu6lxtHaY5gFFPIfUqBKV
rPUK25CT+CSsGeNOk26kq5QHZgy6Q9/rt5JSpWObuwR6oEXK89VhJmOUiES3yXoV8GTJ0S2dDuITUKctqi3BXbPprL0imqSweRyI
YmHi1vulKlNo5sYPmiFukW2aFrHJ8XnATrncV4WFZlBnrVkphMiKTJcoQttgPIdBWSpKwrvBgRYKHrVprTNZJXgfuGn0mmNJuKdk
pWteTSjaEvktyzz3OEgBWPJ39j64VG9bSrGidLb+FMt6sS1FpqaNMadv1NUuJRHYl9tapVSinGMjtmjnHhAkCxbhU0qoXE7oHxL0
qcp1KbVdmpFcRTZoSqAZNZaZXLKQrGQlC+QgDbr4mERtWm7L06+5v4KPWRi46RJsXJQbsmJSZW7LIL8s43OSSFoC8ZGCFDY98CVb
04puIxHCbp7o2bU04sSvLuy3+eZeqkhhTamGZbpyYzntTnPhAUHasR4K9Vpa9LC4n9WanZ9rGoSZTWGKSZUOSrbjMi4sNpz5wSoo
3we8wI3KHdWsEjxSfBtarXzcNi2jb1Vok8mUlE0qSADakPyhS6lSvOSrDyk7Hp7YQ8E5pINwvLdl9WBkxAWBacdQ4FSkPHxiMsVx
lQeKfQ6e8w0sCnZOVKaex3xGWAq5FUlpvdZrIzjV6UZNOmCkVeQQTJuH9OR3tmObmidhtRyzf0Tto4Hiva8Pr4NNMFGHzWFbALxu
9MeiflzrD3m+xUpKkFK0nBSoYKSOuY6Bh1gCDkvIJwYXlj22cMiDuKiOrVnzjvEzWgLLnncTmVGWo4iUBUXyFN8xMOsoDIkLUQIc
GqN0qYIJMOAUDnlJ5DnpDlA4lH2fXaHbFGUYb8doEiUW9toVCAbJ7oEI+zxnaFuksi7LfJEF0I+zOYS6LJXZFRyIVIlhrbaDchOJ
YEF0idSnkTsBCJhF0pCjuSYQhMIR9pk4HWG2UZYgtwIG3U90JqpNS6Z58qyYLILdyUHPCGkJhYnUPAGGOChfHkpDb++5iItVV8an
yU2ULBzFd7LhUpYrhZjS7rcYbQkurKUdAVHA+iMieia6+S56qw1ryTZb80V4prusp6Vo1sVB9mWmpgczAIKHFnvUlXmk+sjujnKy
hnpGOkgkLd5G49I2FchiGEVFC2Sopp3R7yAcjbiNh6ltfUnjWrk4wqQp1bm5tc0AJ/lPYsDl2CEtpwM5GSe+MeOlxiva7vqYhrtw
Nh1DJYcdJpBibHmtqXNY63ig6oI6BYDn471pC8tcKldMmhEy9hcvkoCfNGD1H5YtUGjrKeS5zVjCtD4aSS+0c+a14u7Hluc6nVFX
jmN8ULQLWXVeC2AWAVrQbxdlpsOuOqVv3q6xVqcPa5lgFQrcKa+PVAXTehmvUxQJ8eRT6ZdTyOycbdAU26g9ULSdlJ9scfU09Zh8
hmpjY7xtBHAjYQvPq2HE8FmdU0O8WcLXa4bw4HIjpXQF46Q29rVLt1jTMSLc6WAqoUPIadaWB5y2gdlo79un4Ie/DRXf9ThJAdbx
ojkQd5bxCuOw6DFh37o+QH6vjweSWkbSy+RHRsWAy/B7cEzRl1RmkTHYoWUlAQQ9t1PZnCiPWMwQ4bjj6TvnkDbh53VtUUeC6WSU
Rq2Uri0HZ53Tq7SOhO2nw91aanE0+WpE/NFbgwHJVbYZV87mIASPHMYYpMYrphFDTuvzggDpJACwI6DSLFagQwUrg7ZmCB6ycgtl
HhiuujJyiSkihAzzCcSAfVvjeLNR3PcezcQ32lsVHcv0piBc9rT/ADD52WCeTv8A6n/jCPO+8pV5frTcFNvadZTU6Y2+FFTrBSjC
Crfm9XSPpHF3ASNB4L9atEWnVfbioVmW4irXdf0ohO83pfPJ5fX2yIz8OZrOqR+4V6XiNd3vQ4bKfNq2fArjrT7SutanXxL0S0JB
yeqdRdBQgbJQnA5lrV8lA6kxVp+WqXtiiFyV63jE9Bg7J8QrnhkbTcneeAA3k7guw7wuO3+AzTis23QZ+TrWqNySTaXZhmWPLJNK
CvPWVEggEnlSOvKkkDv6LUZhkboI3a0r7XNtgXiT56rT6sixKpYY8PgJ1Wlwu92WQtY8NY7rkA8PNKv1Zc3MLW4slSyTuYip4GtA
AV/G8Uknkc5x2rGVPreeS2gZUtQSkE9SY0wwBtyuHfO+SUMaMybBLrtRDolZVDgcRT2exSsJ5QTzFStvaSM9+IKaK13W8o3SYzWN
uyBpuIxq34m5J9+XPZY+65zZycmNFrVxs0+sdqYU6cRIGqi6ZEHQk56w7UUYqACnEzGxCsKSeqT+OGmPeFOyt1QQ4XB3JLjaSkKQ
TgjoeohzCdhUFTE0tD2HIqOpJOBg+qJxZZjmuOSIt8isHBPfjuhQbhRyMLDYoEDu6woCjdIEE+bv1P4oWyZylkaQCCTClMBuEE//
ANoW10gfY3CMgqO/UwoCic/WzSeSFTLo+T/2YVF0oM+MIkSuyzBdFkoNZ7hBdLZDsgD0hLosi7MeEBS2SHEcqSSenfAjnK2Zp/Ly
en1rzF2XEOWbn0FqQZ/TC2eoT4KX49yc+Mcdi9RLiNUKGn2Dyju/A+K+jO53h1DobgrtKMXb+ckFomecRzX3u47m571gVd1GqVam
ZmZdV2b8wC02UHaXZ70I8Ce89TG1S4NTwNawZgZ9J4no3BecY93TMXxWomqZDqyP8UW2Rs3tZwLvOdtOxYngq6RsbF5vmU8hgqPf
CEpzWJ9Er0zDbqUNT6ZXHdCXTwE8iWx3QXTgE4GO/GIbdSAJQY78Ql0tk4lrbcQhKlYpDSMGI3K2wqxljnAPdFV4WzST7A5bFvCm
z9M08oyrcbDlvVEqMxPNek7NADnbdHyFJ2wk9RgjMc9SNa+te+o8sbBuA5l69jNS+DR2KlwkfmnC8jh5RPA8BfL1LVi5RwnJEdI1
wXjssMl80ytgjr1iVrgqEkLgozrSgYmaQs+RjkwByuJzv5wh4zVUixzXpVws29TbypfCLIV+YqDEkzTbumnEyM2uXW92T4IaKkEK
KFd6QfOxiJVSIzW3G7lt66q1wj1OxLNNgUh6/wCtBigqb7My/LLupUrl5U+moc/T5XfCpFyFwtcTup3DZVLiqdWtm4Lm0Nn63Mt1
xp6QUuUl1LeUhbrDqhyBzOykZ5V9FYOCBC2Brfwx2haOqmi+s/D/ADTA031GuymrapobU2qSfceCvvSTuGlYV5h9BQIG2IEDaupN
XtdNN7X467XsWv6RUyt3rUX6eZS9FusCYlC8lfZkAtFZ7MJIHnjr3d4ha2mLHRdHwxr00+0VS1vUNqqrUBnlWiV5UH98qBCxjiDo
1bvz4Pe/py8aJVaZWLV1Hm6hLN1CTcl1+SLnCErSFgEpLbh3G20CRRPgdL8clmNSLJqzHlchTWGLllishQaWgltaUg9CfNOfFMIl
XLOmpmOJzjroVRqqFuPXVfJnpkK3Lcs26VAH9i22kfRCoGS9ANUrer+sVtcYVvVSj1iWl/znN249OyLrTM0JaW5iWlqHKodonqnP
WECCsX4KtXlaE/B92xdsytKKc3f7cpUiUBXLJzE6y06RnvCVE/RClKrH4SGwqfpnwU/ElAd5qcq+UzsukJAS2Jh918pTjqnmWoj1
EQiReQK0jnz3wm9OtkvQv4PQhHBtxYK2x8Qkf/4M1Cpu5SODMcvwbvEyegLE2P8A/CEKgrpb4PWnymqvCno1Vqo6FzGllbqhHMOi
w3NNpB8MNziD+1gQtr23f9MvHSpriAywy7T7ErLX3v0UtofDiiD+yk/8aC6S1lyV8G7q8NH+BfVa95xkT33PXiZyZaX1dQpmSS5j
9cUlWPXiBKuieNe3bfpfA1rNWbLcQ7T73MrcBcbOUOLfekgXEepYbSv2qMIhYJxiawaaaS6daIo1k0lkdUlVCgqNO8smW2hIBtiV
7XHOhWefmRtt6EKULSnAXWaY/wAO/FnWJahssUF2XmZtFDS8eREqZSYX5MFpwcBs8mRg94hNyVZHxxXZaXD9weUWxNDbFYkbR1oY
TOfGjM8pTMs4DLPnKTlS1rQlABKgMJOxxAheWrCSRg9REZyVtlyFJbaUTDCQrLGFSEtqhhIVprHJxDaztDCQrDI3lWVKlZsTjKpD
n8oSoFvl65irVGIxkSbF0WAQV7a2N9HflARay2Nq/Y0zaaKI9cbKZC4KrJJmpqn/AC0tKGW3Vj5ClD5J3Iwdox8GdK3XjPkDySfg
u97pDsOq+RrGOHfJFpQ3yS4b+ncSMietaufRHRNXjkxzUVaBiJQqTimuz78Q8FQOKSprPdAoyi8nPdDgmFLRL+MLdMsnPJtjtBdI
Qi8n8RC3SWQEvnpBdJZK8n32hLosgWNvNhbpLJJZJhbpEOwyd4EJXZY2ELdJZGEAdd4S6VHjPXpCptkkg43gSEJJPMcCBNsi5uTO
IEhbdNKJzkwtkoCHP1zDSE3VQSod5MIQmOBSkOkK26wwhRPZcKSEqdTzgHOd8d8QuyKqOs02S0uqQSPCIyFE5gKmyrzjiglGST0A
iF4AF1UlY1ouVsKxqk1SJaqzjTYmZ2XluRo9ryhoLylTgxuSnp9MYOIxmRzGHIE/gLlMZgdM+KN2TXHhttmB61WrqKvlLJPfk9Yt
iAbgrQpwdyb+Meforf1w7kU8QW3KA7OFC8ZiURBWWw3Cel6isEYV+GGuhFlHJTjgskpVxOSqUhJwfnZ3jOnpGv2hZFTQMeCCFvPR
vXqs2dOpnUzZXLyaTyh3zsLIwkAnoe/6I5KuwnkZ2z0x1XjYuCxfR1kU7Z6Uaso2Ee8rpq1eN25JlfNOVx3LqOzKnGUKSnpuBjrn
vijJj2ksDiTNfK3kjsWdLpJpnSSFzasuytmAfWMtvPtTlzcVt1mZekp+uTXKU8qgyoNpWkj9bjIIjKmxvSGpZZ1Qbc1h8FkzaSaV
18RD6x1jcEDLp2J6x+IOsoWpuWqDkwy8EoWxOff21BPo7KzgjuIjPhx3GsO1rSFwIzDvGHvWXBj2P4USBMXtNrtd4wy2ZG+zco/M
r5qfdHCcvJ6IXneo/grq6UdjPyuXVoV5MMBPf50fR+Mfph0L9d9FD+bdlvVloZzHV66O35jzadTfLzjGR2ye6GYCLzzg+gV2ulo/
/btE5v7Uz/KVRacXpa1syWn2m2gSmk3VfbUi5dl0Nec/KoUAp5lCjuFgBYwNkjpknIs0VRDGyGko/LfYudvG8j8bFs6Q4TidbPiW
P6RD/p6UyCCE+S47GuIG0HI32uPMLLkHi2v5WoWut31gMql2JioLYaR2vPyoZAaSrPr5ObA23iu6ds9TJMN5+GS1qHDnYVgFHQON
7MBJ2Zu8b3Xt6lzfUlKStWY1obFef4mXtcQodLY8rqbCVOBpKVha1kHCQNz0iad2pESBdZuEwCpr42OdqgG5J3AZnZ7udVFQdDjj
rgUCFrKsjvycxchaRYFc3icoe572naSes3VapfgYu2XMPkRKcyMHYQoaoHzE5JHMR1h9lAXkJQVmEsniS6lo5VtJQs4wcg+ERWIc
SFoNex8QjcbWSXEcgI6kDrD25lQTNDQQDmo2D7IsALFLyhy4GMbwqYSgEw6yZdKCcQlkmsUYTC2TSUoNk7kwJEYbyMwqEtLXeekJ
dKAlhrJ6Q26dZKS2c5EISnBqWGsk5EJdODUfZeo4hC5LqIi1gYAhNa6NRS6RTpaZmVzFYUW6XTwHZxQG7nzGk+KlHb2bxSrql7GC
OEXkfkObiTzBddojg1LVVLqzETq0kFnPO9x82NvFzzlzC5OSr7suGbuioGbqADTLY5JWVSfMl2x0SB4+Jgw+iipItRmZ3niVFphp
XW6R4gamfxWNyYwbGN3AfM7+hY52RWvpGjrWC5DVJUxiRJxgGGlykaxT25IgDaG6yk1VIRJ46DMIXJwankym/SG66cGpaZM+EJrh
ODCnPISR0MMMgUgYUtMhDeUCeGJRkuUdITlE/UQEtg+uEL09oUlmXJUMCIXvV6A5rdOgV7Uy2qs9RdQZV2pWRcXKxWZVvBcZ7kTT
GejzZOR84ZSesYdcyN7g527ht/AXqGi1ZUMbyULgH+breSTva7912w8MnDMBOa/cPs1pFcgbln2qrQKm0Jyi1eWGWahKL3Q4g9x7
lJ6pUCIZDWPY7k5DfeDuI4j58DktSvwKnr6Y11GwtIOq+M+VG8bWnm3tOwixWlpuQ5ScJjYimuuCrMPLDYhVj0kT0Bi22ULClozw
UM01RWCQcAjMTNnAWXLQOO5ddWPfdtzekOi6be1mpell76YJqzb/AJfSpp5ZVNPFQW2ptKklBQcEEd8WRIDmFjSU0jDYrK39c7xk
qZNBPGdQqg6lLjrPNQJpx5C+Q+ay4prLZPo5BHWAycyZyLlaaBcQWh9W4L3dG+Ia5rio02/Wpqcfdp8q4pagqZL7a0rAIOSdwRC8
o0oNPINoVprPxTaHU7TLQ/TzSGvVir0nTy66fPTU7NyK0qZlGFlS1qJA5lkqOyRC64TOSdwWv9deKHTy8PhD7N1St+svTNmUZymG
bnxJOBSOxDnaYbOFKxzJ98Oum6pstqS3HHpJb3EjrhqhTrimnZquWtKUy0VIpTilOPoZJWog+iA4EDfqMmC+SS2S1vpn8IPMaoaN
as2TxXXa/NKuOg+S2+8ikJPK8UqyFdkBjzgg5PthbpLZLEfg6OIeydBbuv2oaqVN2lMV61k0+SWiVW92j3acxHm9IS4TtVyx3gH1
XsPRbiK+7jVepuyFNpVNnBIFEmqYLsw8SgDCfRwgk5g1gl1HcF0Nw7/CdVSf1kudjiOurn03q0nOtSDaaSgCVJdPYj72nm3aynfP
XfxhNcI5J1lrS7tftMJT4Pu4NIbWrz8xcKrucm6dKmRcRzyYqAcbVznYHsUpOCc5GIA66CwqXrPxf25rnwI2Np7M1CdmdTKTPSUv
NSAknFmYRLlTaFpWMhRU32e3UkGAnNGquP16XXeXcpti5iBscUSZ2/xIWwuku61l1hwMa66d6PWLrFpjxFzVfteXv1hlgvsyLgcb
bLLrbiCMcza+V1KkkjGMwXsgjJbEq+vHDfodwmao6c6DXTc911O/2XGmmZ+UUktuONpaKyspSEoSkFXeSRjvhNayVsZcbBUHBTxm
WhoLwp6m2dctUmZO6Z96fnLbl0yi3EuvPSaW0DnGyfvjac56ZzCa4TzTyA2soWm3GFats/BwXdpPVqo+3e7iZynUmREqtQelJl1C
lK7QeaBhx/r4euDXCDC++xa/0T19suyeBHWHTOv1OYl7uu6p+UUqUTJrWh1vklRu4Nkk9kvY+Hrg1rproy3JZzQuNW2q18HBcej9
71GcRe8i0im0VoyynEzkmmZaeaJcGyeRIW3g9zaeuYNZBYb2W4NZtcOFDiYs7T2Q1Qv66afM2TS/J2kUuQcaCluNMpcCiUqzgsjG
PXDiUmoTsWA6Ra8aH6J6d8SFk2fc1VmKRedPVL2k7OSTjjs4VU9bZC1ADl+/L5dwNsGGa4UraeQ2yWJTOv1hao/B6ymlepFaekNQ
LHne2tkKk3HUzLbJJZQVjZILTrjO/QoSekIZQpRRya1rLjlimrQBzJO/4IrmYLUjoXDcpjUmR3RE6RXmUh4KYzIleBiIXzALQhoS
TsVpJ0NTykhKCVHoPGKclXq53XQUOBvlcGgXJXU+mOnFF4etP2dUdV5JiertTQTZNtTKcibcHSdmEn/e6DggH01Ad0Z75TNqudsP
kjj+8eYbuJXZspG4a2Wlp3Wc0fnpB5gP2TD947ziPIbzrmu+Llqd6XFUK5cs49UKrVH1Pzcy8cqdWep9Q7gOgAAjVp26osvMsWq2
yyHVFmjIAbhuCxV1gk7iLzXLmZLkpky2e6JA9VXAoeSQuuFGWlF5Jn5MO11HqlASvhBrpNW6V5N9MGum6iHYGHB6QsQ7EZ3Ag103
VRloDuhdZJqoi3v0xBrJNVJ7InrmF1kmqiLY7oUORZEW8euDWSWRFnH1QayLIi3jeDWCLJPJmFuElkkpz6W8OBTSE2pJx5oxC3SE
JBSRtCpLJtSTvkQt0iQRtCIQAxuYEwhFzeMIQkLU608psZB6euInMuq8kQcnhNIKsuJTv1IODEZjO5QOgdbIp1M+ACiXHZpV1Od1
e0xHyO8qE0x2uzKy61lIpjMxN1GbbZTMybjbMsPOXM82w26BORnJ8Iy65plsxjb2IN+C5zFAZy2KJly1wJO5tviVXl9WACScDeLW
qFa1Akh88/WCwTtQWSnQp4DlHnD8MICAkYQ0qK1OcjmD1HdDiy4Uz4bi6tpOc5ikuL5E53J3x9EV5GKjLFYZBXUrXXSy3LpUEMtr
KkgDBJPeT3xRkpm31t6zJaNmsXkZlZfQa6pr0l5SRjrGRU0gO5c7W0QOwLOpusO1Kmyc+XgUtIEq6M+chSd059RT+KOfbStjldFb
nXLxUjYp3w6uZ8Yc4O3qKu7Hu0y9SaQVghSx39d4o4rh2tC5wG5ZuL4XeIvA2Loz40T84+6PJNV3BePWfwWc3J2pqcqWltJ/O6cc
ydzuY+kMWH57Lgv1p0aA5E34pWl0xMDWe53JkjDGnE0SUjAx2ghmCk98zE+gfiu+0gjZ+S9I1m+qZ8Fxxw5XR9zvEHZE29zKbbrU
u24lJxlLh5D+BUUMK1YqiKTn+K9Y08L63Ba6mJ8xxHSMx8Fr/WqlihX5cMhLpWPJKpNS4S4cqQEPrSAT3nbrElONWRzTuJ+KycVk
M1BTztzL42G/S0HJaknpcuucgUknv39H2+qNqJwAuvM8Qp3SO1QfoqSdm0sFKJJSkhCgouDYrUOh9g7hGjFHrC71ydbVCEgQG1s7
7yRv6BuCr62hKnUPNJKUzKA6pONgo5yB6sgke2J6Q2Bad2SyMfY1z2zMFhIA4jcCb3tzXFxzFVSgfk7xeXIP2ocuem5hwUDkkDcQ
+yhLksJzsnJgRmpDbWME7D1nrDSrDOdOIBIwvcdB6vVBbeE5kt7tcm1tFGxBiUG6z5GFpSOQeGYXcoTmjSg9cQJEoN5xvChNS+zA
hUiUlHtB8IRASw2IQlKAlBsq67eAht1IAlobyIYSnBqeDH/vxhhcpQxOpliRsIjMilEZTyZM42EMMouniIpKpFQBODtCcoEckQq5
8PCXSmZPKlCytLQ6JUduY+Ksd/dCta3XLhtO9TyVc7qdtOXeI0kgbrneeJ+CqHUKfXEwNlnkEqXKU3OCRCF6cI1aNU4AYxEZkAUo
jUhEhjqMxGZU8Rp9EjkbCIzMniNSEU4nuiMzp4jT6KYfCGGoAUgiTqaSe4HPsiM1ITxEnBSVD5OfohO+RxThEUSqUrO6TB3wE7ki
kGlEfJg74CURFLbkVIPSGma6ma0hWEqoskHGMRVkzW5h1a6FwIK6c0J1Iot82k5pRq9MBqhz7pct+sOecqgzytgr/q7hwFp7vSEY
8rA08m42adh9E8eg7x69y9hw3EH1OriFENaoYLSR7p4xu/7jdrDv2KirvA3qqiqTUtJWXWptLDpSH5ZkONOjuUhecKSRgg+Bi5CK
2MWfEb+5V8WdoxVuE0FdG1rs7OJDhzEWyI2EKomOBfV9Az9wVwf4MPtRY75qBtjPUsB+HYC7ZiEXtfRVM3waarSgPlFi19vHjK/5
4BWSDa09SYMFwt48SriP8ypZzhL1PbBzZtfH97f54e3EQDmCqkujFM/yZ4z/ADBU8xwvalS+Qu0a8n2y+PyxOMUi3lUXaIuPkvae
ghVszw2akDZFqVv2BkfXD2YrT73KpUaF1pF2gH1jtVe7wzaklQ57UrQ7920j+VFoYpT+ksx2hOJHPU947Uj/AEL+o6zk2jWlevkR
9qH+E4NzlCdC8QBziPu7UhXC/qMN/uQrX0pb+3DhiUPpBRnQzEN0J93am/8AQ0ajt7JtCtA/sG/twDEoD54TTobiYGVO73dqJvhq
1OWrDVnVz6EI+3Egr6Y+eFXOieLt/V3e7tVpI8J+rU2fzvY9fXnwQ39uDvqE7HJh0er4/LiI6u1XcnwTa0TRBZ0+uIk+CWh/LgMw
3JBhmr5dgp6+ArXBxGfzO7jwf1rR/lw0VFtyd3jTuGcretPUDgv19s+v02tW9Yl0SdVpE03NyUw200Sy82oKQsZXjYgGJBV5qB+D
xaps9p9a3zN39x4yKFKml3ohJ3z8Wym3+NDzWMAzKpswV7zZpB6CFzDq7plrJfF6VO7NUqJXJuv1ZaFTs28y02XChCW0+alWBhKE
j6IqvxmkZ5UgC2KbQjFalv5qnc7ot2rX6tK7plzh2jT6fUoJ+1EBxug+9Hv7Fps7n+kAH90f7u1JNhXC3sqlzafpSPywnhehOyQe
/sViPQLSC9u9He7tTrViVtQx8WzXs8364Y7F6MfaBXWdz7Hnfqjvd2p8aZ114ebS5s+zl+uGeHKMfaj3qUdzLSB/6m73dqdb0huV
0YYo88oHwCftQ4Y7Rn7QKOTuYY+39Ud7u1Sm9FrwG6aHUvoCftQ7wzSH7QKAdzrHR+rO9ynymil5LOBQKmc+pP2ojdi9LueFah0D
xlvlQEK7ktB71VgJt2pb93Kkfyorvxan9JaEehFcPKZb1q/kOGPUOpY8ktSqOZ8Eo+1DRiLHeSbqR+izo/0j2t6SriX4NdV5kjsL
Iri/2LKT/KiQVMhGTCm+BKKM+NVRj+b6KxY4LtXG1DmsWvD2sJH8qInzS+gepXYaHC2nOsi9r6LaOlPDmxpKxPX9xI0yZp9Ct9SR
I0V/lS9XJw7tsJAJ+97ZWrw2ihIS460rSGDdsLjw6OJ4LoIJ44wKXCZGvneCTIM2wsG15/e3NHHNaU1r1WrOst6TlwXM6kuvANy8
u0OVmUYTs2y0nolCRsAPbFmAvLzJIcz+LDmC4vH8TpooW4fQ/omXzO1zjtc47yTtWrpiUKjskxqMlAXn8+aZFMKtwDEnLhUjHdF8
VKB9EwvfAUZiKL4pV15fwQ4VATORKI0pQ7j7oXvgcU3kSkLpqgfRhwnCYYSmzIkd0OEwTTEm1ShHQfgh4mCYYymzLHuEOEoTTGUl
Uv4iF5QJpYUlTPhDhImliQUbdIdrJNRICNjgQ7XSaiAbJ6wmuk1E4mWK+4w0ygJwjJSlSagNx+CG8sE4xEJpcqR0EPEgUZjKZcYK
fVDw9MLEytHhEocoyEytPXaJAUyyaKTDkhSCgDMCakEc3UY8IEJCgQTAksjxgbw1Msi5cQFIU600Vq22A6mGONlC94arF99SUS6M
57NkAHxycxXY0XJWYyEFzjxKJFRUn0jkeuAxApXUgOxSWp5LpA29sRGOyrvpi1WEtONtecltDjiSCkqJ2+jviu5hOW5VHxOORyCq
6mC44qYQkJ5leckdAYsRcCrlLkNQpMpNlJAKoHsTpYgdiuWJrAG8VXNWbJErmTqXIBhW+IpyQgrNmprrP6JeSZWXdoNTWHaU/wAq
yAkBTDxSMOpPXI6Y8Mxg1FG5zuXZ5Q944LlazB9d4rIhaQZdI4etWNssuouOWZBypMwgHHRW4xj29Yp10jO9XOPAqniLmmjc7mK6
98jV4GPEtePivnPlQs4lnJmrrYmatLqQ+2gJASMDGfAd8e7zySTu1njNfr/RU0FKCyI5KTaU2li/NRltIdQuX0wmeVSxjP31O4h2
HO1X1J/9s/FdXXRF+E4Wwm4NYz4FcCtB2l1+WmqYpLsy0+240Gt1ocSpJAI65ziMunc7VbbavZ8UjDp5iT4huDzdKzDjVlpama53
GJRJRMzfk83PNcuAzOPy7bkwgeoOKV7yO6N+SJvfj7c1+ki5968qw6slGjdPfO2s1p4ta4tafZAXNE0hYSFJO7mQfXGgzVuuTrGy
BmsN6pnmRnLuyfx+oRda47lzEsbftNijuFLuFKKkqJwvO6SjbAx3ERO1pGX4usySVkmZNjsPC27qUKZliyfN5Sk7pUk5BEWI36wW
JXUhiNwQQdhGwqKEnJOcCJ1iORpb5hkdIcorXzTo5SobYSOggTi4XTnpHryjuzChI9+sUoBQIyOsKoiSlgkjB3HhCWTte+1JU1g5
T0MOByUTxnkhyYHfC3TEfZkdYLppCVy+qC6LJQEF0WSggd++YbdOATyUZERucngJ1DWTETn5KZrVNZlicHHdFZ8tlaZGrKVkUrIB
HfFGWosr0cN10FobwXX/AK6MNz1s0tEjRFq5fjeqLLEur+x585wj9aIrxuqJrmNtxx2DrUsjqeD9I7PhtKxPiM0ttrRa8hZtDuZV
012koIuCZYlw1KSswccsu0c8y1AbqJ6ZAhaWWV7nEkFuwEb+Pq3X3pJOTMYcBYncdtudaQnZLyhRA6RqB9lnuZcptih4wSAYQzpo
hU5unhob4A9Zhhmun8mprEsgjYp94iu+UhTMjVlLUjtgCkD3xTfVaqstp7qxZtxascqRiKjq8DepxRlTWLWcUfQMV34m0b1M2iPB
WkpZkw8QEMLV7BFGXF2N2uVhmHuOwLIJDTKemiAiUdOf1hjMm0hhZtcFdjwmR2xqyGU0Lq80kdlIPnP/ACZjMk0wpWHN461dbgMx
81Nzuhdalc89OmBjxbMPi0xpH7JB1odgM481UkzpTUWs88k8CP1hi8zSWB2x4UBwaYeYVVzGnM83n87O/vYtsx+E+coXYVKPNKrX
LInUKP53cH7WLQxmE+com0MoPkpLdBm5BXMptaceqEdXRSZXWtQVVVQyiWJxDhsWRt6iXRLtIbTXKylLYwkeXugAeA86G3ad/vK6
5mnlf57WE87G9iZmNSLrIymvVj/D3ftQ9gZfP4lSP04qiMmM9hvYquZ1Du530q9V1AeM86f5UWQ2Hf8AEqo7Tav80NH8rexVc1qD
dichVdqw/v1z7UWI4oDuVOTTXEz5w9kdip5u/bke/Ra5VT/fzn2ottgh9FZ8ul2JOP6S3qHYqx+76+oedWqoR/15z7UTthh9AKnL
pJiDtsxVdM3XWFenV6kT655f2osNhj9AdSpSaQ133zusqA7dFWP/AAtUf8NX9qLDYY/QHUqMmPVp+2d7R7VDcr9TcJJqU8fbOufa
iURxjzR1Kk/F6p22V3tHtUdyt1I+lUJ4/wB+OfaiUMZ6I6lXdiE5+1d7R7UkVmokf7Iz23d5a59qFLW+iOpRd+zn7R3tHtTrdeqy
Dlup1FPsnnR/KhDqeiOpL35OPtHe0e1SkXdXG+lZqw9lRe+1DdRh80dSkFdOPtHdZ7U5931xN7Ir9aHsqb324OSj9AdSU4lUbpXd
ZSV6h3Kpko+P6zgqyT8Yu5/yocIIta+qESYvW8lyYmKhKvi4l7KrlYI/ti99qJeSi9EdSoivq98zusqKusVCaVl+fnXFHvVNuKP4
VQ0xx+iOoKVldUH7V3tHtTiFTDvpPzB9r6j+WIzyY80dQU4qqg/au9o9qeRLvk57V3+FV9cRuez0R1KRtRVbpHe0e1SENvox99e2
/wCUP1xCSw+aOpWG4hWt2Su9o9qmsTL6cYfc/hj9cQPYz0R1K9Djdc3ZM72j2qzl350gckzMD2Pq+uKrxENrR1LUj0gxK1hO72j2
qW38YK6Tc0P74V9cQudCPNHUpm49iX37usqQ0qptnKZyc+iZV9cMLoT5o6lI3SLFWnKd3WVPZqNXSRien9v+cr+uInCD0R1Kw3Sr
F2n9O5XEjXa6jARUqmnHhNL+uKkggHmhXo9McXGXLHqHYr+Uum5gkJRWKzjwE679qKzpIgrbdMsTIzeD/K3sTy7iuxwebVK2of8A
XHftQwVMG8+9B0vxW3iuHsN7FCnlXDWW0tVWYqU0hJylL7y3APYFE4h3fdO3MELPrNJMXqojE9+R22AF+oJEtY84/j87ukn9bET8
Zib5wXNd4TO80qe1phUHscko8f2hiF2kkDfPCTwPM7zSpLekVWUQE0+ZP9zMRHSmlH2g60eBJ/RKsJfRGtPEYps1/BGKz9L6Rv2g
604YHMfNUpzQqtNjK6bNAAd7RiMaZ0hOUg60/wAAT+iqee0oqEuCFSbySPFBi/FpPTu2PCrPwSYeaVQTdhTTJIWwsH1iNGPHInbH
KnJhcjdrVVv2e+g4LShj1RdZi0Z85VHUDhuUB22lJJBSB9MWW4i071C6jI3KC7QlJyPNGPWItNrQq5pSobtKKT1Tt+uETtqrqM05
CiOSQB9JH74RM2e6hMSjuSqcbKTn9kImbKVE6NMmVPySPfEnKpnJpTcoc7w0yJQxbZ0F0zousN8ydm1K4ZK06tU2Smkzk60pyXnZ
nIww4Ru2opzykdSMdSIxq2aaI8oD4t7G+VuB6L5c3QtCAxahBbcjhvWe6zcE+omjEo9P3JSET1FaPnVWlOeUsI36rx5zf7YQPmqI
QHSNyO/aOsKaJtNPlG7Pgciuf5ykhpRCRnHXG8WYavWUEtNZVE1JlJ6GNGOZZ8kdlXuM4zFtj1Vc1R1owTFgFQEKOtODsIlBTCE2
tMKksklI3gTbJCkAdQYEIy33nrAmlBDRWoAf/wBoaTYJjzYXUkkIb5EjCc9fnREBc3KqahJuUMhbYx6SenshtrFNLCCmFoJBEPUg
SEultWM5xCFt0rmXUxiZKSPGIXMVKWHJTy4hafvg5kODcRBYgqkAQctyqn0dg8UZP60+IicG4V5h123U2VnEp2woEAbZ6mIXxlV5
oSc1Zy7qlY8TFd4AVCRgWa23bMxWWF1aozUvS6M04lt+emMn74APvbaB5y3Mb8o7tzGNU1QjPJsbrO4fM8y52uxGOnkFNG0vlIuG
jhxJ2Bt9635pnqhbdDZlGLap8yury2GGqnUmUKUWsg5Sjolec7+EcXjFDXMa6QkZ32Z2XnGPYVixc6WV4a03Oq0nb69y3f8AHiv1
RMePcg/nXjHeXMs78v8AJCAJibUPU2I+gXkDev17omF5sQFTC6Xpas6jOtqccI0wmmwpwYIKn0gRFTTWdU/9sj3r0aDDGSUeFtP7
Yw9TSuG5C6pyz7zYrdNdCJ6mzgfl1kBQC0kYyDsdx0MOp2EMaW5ELqsaljNTOyYXa64Iva4ORWwbj1CtfiFm3ZvUl5q2LxdSkLr0
tLKclKkoADM0ynKm3CAPvjYIPekdYuPe/XMjvKO/cekLj4qZkMApKXx4QcmEgOZzNcdo5jsGwnYtban6MVvTZEousty8xJVJgTFP
qMk8H5WdZzjtGnE7KGcgjqDsYlZUESBrha+znVGahhqKJ8tO6+obOaRZzT+8Dsvu4hakqbeACo9Y2qc3K83xVhDblVZPm7Hfwx1i
6BmuXkeNUi6QhaVpDToCUcxPaAecCcdfEQ8tIOsFHHURvZyEgsL7RtF/kkTMkZdZbdxzJ643+mJI5A4AhZdbROp5XRu2hNBIwAOg
iZZ9kpIxnA3gTUpDZO4hUhBKdSydsjB9UF0mqUrssHPvELdNLbJQSTuBse6ETSCjCATt0hbpLIy3np3QXSWRchxDbosjSjOAYLpb
JYQM7CGEpQFIaa5ohc6yla1WUtIFzGBmKkk1lciiJW9+FHhlnuI/UtNAaml02j05gTlan0I5lMMZwEoHTtFnITnYbnujPfNrODQb
X38wVh+rCzXdn2rrqf4VrRv3jJVaUrJMyunmk9q01M1IsjCptxZUtLK1jdSlq85ajuRtHPYrjFJQNdJK6zbnpIaBe3OSbcylileK
UOHlO2c3/Cy3jH48rf0KtR+0tJ3aXO3kZcysq1I8qpehN8vKFr5dgsD0Wx37mM/DMTxXSSQFjDBSD1OfzD5nd0qBtK2D85L4zuHb
zfFePz92VN+cmZmbWmbmJt5Tz70xla3HFHKlKPeSTkx6IKOENDW5AZADgqjquUuJOd1a0u9ZqV5VKptFex+ryqlZ/wAYRSqMNZJ9
o8dB+iljrXDzR1LJ5LVuYYIBtmzHP7JTFn/zIyZNHmu/WZR/OP8ASrTMSePs29X1V3J61vND/afp85/ZaKtX/mxRl0Za4/3qb1PH
+lT+FHEfo29X1VzL6+OpSAbD0wOPG31/z0Un6Jt/bJ/8Qf6U4Yi70G9SsGuIiabI7OxdNEAfNobg/wDNis7Q6MjOsn9sf6VMzFHj
zR1K+p3FBOsco+4PTRWPGir/AJyKMmhEN799ze2OxTtxaU7gsvpPFhNIUO00/wBNceqjKH8uKMmhsLf1iQ9Lrq1HiDztJ/HqWZUj
i4WyQVae6en9jTVJ/lRnv0WY0/pCenP5q9HVk7XuHQ4dizSlcawlgObT+y0etuSUPyw3wKI/JjjPSwn/AOSmD437ZZB0OHYs5oPH
LKDlMxZNAQB17JjEVnwVULrsp6c9MX+5MdR08m2eUfzKbU+OelrClKsuhK2/TGYVorJH3dS0/qi/3IZQ0sY/vMvWsMq/HbThzBqw
bSXj50sTGg3Dp5NtPAP/ABn/AFoLqaP9YlP8w7FiM7x2NFZ5dOrFI/XSSj+WLLdHg43McY6GH/Wou/Yxsll9odipZvjkbeBA0209
ye809R/lRONGmnc0dDT/AKk3wiBskk9of6VSzfGIZrONN9N8HxpS/tw/8m4/St0X7Uw4i703e0P9Kp5viw5sn8zbTL6aOs/y4UaL
Md9s8dB+qYa9/pHrHYqmZ4tnmyeXTnS8D+0aj/5kTDQ+N2ffEntKF+KPG89Y7FCd4vXlDH5nGluf7RK/nIl/IuP9ok9pQnFpOJ/H
qUN3ixfe9LTrSv6aAr+cg/IiMbKqb2/omnFpPx/wq2a4oX3fQ060p/8ADyv52JmaFxj9cn9v6KJ2KSHh1Kre4m54nzdO9Kv/AA6r
+diw3QuD9sn/AMT6KE4rL6I6lEe4jJ2YPnad6U5/7Oq/nYmGiELdlZP/AIn0TfCcp2tHUoate5pWytP9K8eH3Oq/nYd+ScW6tqP8
T/ak8Iyeg3qSVa6uEYXp7pV/4eX/ADsKNFG7q2o/xB/pSd/u3sb1KK7raVgj7gdL058LfX/PRK3RcD9dn/xB/pSHED6DepQHtY3C
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
XKdMyvIvphxtQA9+I8noNfD6yGr3sc09RF10tThrXwuZzLxztC0JusXrQ7eWjE1N1liQcR4K7YIUPwGPtfEMQjhoZaq/ihhd6tW4
Xk1NA59QyLeSB717Zyt1CUqjUmwoBmVWGkb9EoGPxJj4eJnMTnX8rPrXrj6KPk7kLxa1DuFy6tSrrrLrhdNUrk7M82eoU+sj8GI+
28KphTYdTw28ljR/SL+9eSzPDpXnnPxVL2qhF0AFRXReUH1w8MCTWRF9ULqhJrIKdUYTVCW5SSjtBgwXsjaum/g5b7kNPeJBlqrT
iZNFzUeZpbC1q5UqmFKQ40kn1qbKR61Ad8cJ3SKeWowJ0kbb8mQ424WIPVe60sK1RPqHzu0LO+MvhTlk60WnN6VybcoNS6muTmpJ
tOGpOeBClvJA2DakKU4R0BQvGxjktANPxNhdUytdlTNDgTtLNgHSDYescFqYnhZbMwsHl/i/4+a601fvq2eHrhKuGgW0GZSlUW3H
aRTQMJVNTL6C0Fn5y1rUtxR67KMefYBjOK6R6RwwkeK5+u7maMz0ZZdQWhUYeyjpzM/d+AOuy8jKbUQqXbCnDskA+6PpuWGzjkuU
bLfNeiPA3TpDSDSKvakXW6JRFWZU8p5XpNU9jOMetaycDvymPnzui4lPiWNw4TSZlptl6buwfNdnh9E2OhM8m/PsW6NC6shMvVtR
Lpmqc1eN/LTMuYnWiql09IxKyKTzebyowpeOq1HPSOe0hxOSlLMMo2u5OHK9j47/ADnbOOQ5k6loopfzkm/d+Pxe6zOsatIb5kpr
0uCOv+mjY/lxy4diEpvqv6ndi1YqWiac2t9y19XdTjN82Lklh4f6ctfzkXIqOpcfHjcf5Xdi2oe8mty1R1LXNdvIAqW7c1PA7yuu
Mj/zI3qWhkNgIHew7sSST0489vWFoXWjiuRpsyafZs+xWrnmG8pfbmhMS1OB6LUUkpcd7wnOE7FWTtHoWjHc/dijuWrGFkIOwizn
82eYbxO07uK5nHNJo6NvJU5DnnftA7Tzda4zmp2oXHVZqp1+bmKhPTzpemJqYWVuOrUclSidyY95p6eKnibFC0Na0WAGQAXl0sjp
HlzzcnepLLIbHdiLACjKNbuNk5EOTSo61ZEImEJpXTeEKapszN+TSxkmEpAc5VPrxu4RuB6gIqtbru1ysyOLlJOWcdmwcFAWvfGI
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
XI9F67zqyU/zlMNThzdlO3qVS/x8agPejXZpB9S4tDRqqBuamT23dqUV1ENlOzqVNO8dWpSyezumoIz4ORcZo9L500h/nd2pjsQp
hsgZ1KmmONbVF3PJedaSP1r+PyRZbo83e9x/md2qE4lFuiZ7IVY/xmaqHIN8XCAe8TX+aJxo9CdpPtO7VEcSZujb7IURfF9qg4N7
+uYf38fqh/5O05yLT1ntTDiQ9FvsjsUGY4r9T3Af9Xt0f4efqhRoxQk5xD39qYcUduA6h2KuXxX6oIP+366/oqJ+qJvyVw4jOEe/
tURxN/N1DsTK+KvVB3Y6g3Xj1VE/VANEcL/Z29X1TTiknN1DsUd7ij1NCD/8QLuz/bNUSjRHCt9M3qTDicnH3BVUzxP6oudNQbvH
7qKiZuh+CnbSs6lC7EptzvgoK+JbVE7/AJoV4fxquJhohgf7Iz2VEcTn9JJTxNandDqFeIPqqyxCnQ/BN1Iz2UeE5/SQVxI6mudN
Q7z3/wCmHIQaI4LvpI/ZCQ4jN6SiucQWpbit9QLzPtrDkO/JTA/2OP2Am9/z+mUk69ajK9K/LxP7sOwh0TwP9jj9gJwr6i3llSGt
eNQMffL5u4j11dz64hdolgu6jj9gKQYlUD7Q9afGu97kefet1q/dZ364i/JHCN1HH7AUgxSf7w9aUNcLwX6d4XQfbVXD+WEOimFj
ZSR+yE4YpN94etSGdbrqSd7suT6ak59cRO0Vw4/qrPZCkbis33h61YNa73Un/wCbLk/jJcVn6JYcf1VnshTDFZfvD1qfL8Q11sHa
7Lk/jJcVn6GYa79VZ7IUgxeQeeetWbHEzdzYwLsuPPrqCoqv0Fww/qrPZCkGMO9M9aTO8Tl6zLZbVeFyFv5vxirELFoJhLDcUjL/
AMITTiz9oeqKZ17ul7JXdVxE+uorjQj0Qw4bKVnshRnF5bfpD1qhn9ZbmmMhy464seufWfyxpQ6MYe3ZTs9kKq7Fpz9oetY5UNQ6
1N57WsVNefnTaz+WNSHBKNmyFvUFUfiEp889axSq1afmgtbk5NK8eZ0mNeGmhZYBg6lQlmkdnrFdzcONsSmkGjUs/NdnLVS5ZUVi
459exZlMczLJV3JCBzkd5X6hHz5priEuN445jc44jycbeLtjndN8ugL0nR7C20lEJpMi4axPAbvctJ6BXxU69fd81RNSo9El7xqH
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
PIU262rCkKGCD3giNZr2vaC03BXmlRTz0s7opm6r2mxBQSg55mc47x3ph99xTTFc68fVwT/Z5a7RI2TgL/WnuPsMM17O1SrApXPi
5Vu7bzJlSOY7RMHLMkjzySCnHo9e+HKu5likkY3ByYVRObZJwc5TCqJzTtCcQ4ds/RCWSAp0PEjHfCWQSj7XIGD0hNVR3R9sceuE
1U0ptThG8KGqNySXc474XVUZKcQrPXENISXUlo5MQuCaSp7CQYrPKjLlaSjAOM4ijK+yjc5XkqmWkGFTk1ylLO7bZ37Vfcn2d5jK
nke88m3f7gq+q6Z2qFm2nlL1N1FZmpmxbTXX5WScCJl6ToiXG2lkZCSoDAOO6MmtpKCEfnHuHrKvQYEZ82e82WwpbSjWzbm03eBP
z6KmMGSTCR9q7rd2K83RWYjaPaHar2n6P60KAKtPZVP9kpCPrjPmnwvdLJ6tbsT/AMkHna8D+YK8lNJtZWsZsClHHcqjIP5YzZZ8
Ld9pL/V2KWPRAg5yN9odqv5HTXWEqSlenluNg9VroyRj8MZczsKAvy03W7sVoaJMv+lb7QV01pfq20rmFlWav1KoyDFB1RhJyMk/
W7sUzdF42G/KN61aytjauNox9wFgK/Z0RvP44rOiwp5uJKj1F3YtGDCmMbYuZ7lFmdNtYHphbjdgWKEqOyU0NBA/DE8ceGBoGvUd
buxV34PGX35RnWEX5ler7g309sj6KIgfliQQ4edj6nrd2KTwZDb9IzrCYd0a1cf62HZzZ9VIQIla2jadtQfa7ErMNhDv0jOsJkaB
6rvK++2hbSc/MprYiTlqYbGz/wBSuClgb9qzrCeHDhqa6PPtegg/9QT9UAq4wco5+pylEVP96zrCQrhm1IB/2sW6CfGng/kh/fw+
6n6nJ3JQfes6wpMvwz6ijHPbtuj9zB9URPridkM/U5KGQD7VnWrJrhk1AUMmh26k/wBqx9UV3Vsu6nqOpykDqUbZWJZ4ZtQUDPxJ
bpH9qk/VB33Na/e8/U5Lr0h+2YlNcON+pPnUCgn2UtP1Q01U52QT9Tk4Gl++Z1qe1w7X0kf7BUEH1UlP2Yj5arJyp5+pydr0f3zO
tPDh7vwbGh0QD+1CPswF1Z+zT9Tk4S0f37ES+H2+EjegUNf7kJ+qG69b+zz9Tk7Xoj9sxIRoLeoOFW1QPaqkD6oQy1Y+xn6nJ16M
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
71/vT/yN0M/Y4fd2qQmxbOHWj26f2yPriM4vim6V/vUTtC9Dbf3SHqHapLVi2UsYVRLcPsUj64jdi+LDZM/39iqv0M0O/ZIepvap
Dentj5BNDt33o+1Ebsaxn75/v7FAdDdDxspIeodqnM6d2MetDts/Q39cV3Y3jP3z/f2KJ2iGiW6kh6h2qe1pvYR9Kg2zn1hv7UV3
Y5jX30nv7FWfopoo39Vi6mqY1php6r07etb6Q39qK7sex0fbSe/sVV+i+i26mi6grGW0t01Hp27aR9vZ/ais/SDH/v5Pf2Kq/RjR
ndTxdQVpLaVabnZNr2grP6xr7UVpNIse/aJes9iru0Z0e3QR9QUsaT6cI62vZ+/ihr64rnSPHT+sS+/sUX5N4APsI/ZClS+kmmqv
StOzVePmN/aiJ+kmPj9Zl6z2KB+jOBHZAz2QrOX0g0uwM2XZRP8AYm/tRXdpLpF+1S9Z7FSdotg26FnshWkto9pc4MCxrKX7GG/r
iq/SbSIfrcvWexVX6L4UNkTfZCspXRjS/I/1BWUfV5M39cVX6U6RftcvWexVX6N4YNkbeoK/puh2lz+AnT6x1kdR5G0fyxUl0t0h
b+ty9Z7FQnwGgbsYOr6LJ6doHpgggjTixT7ac0fyxQk0z0hH63J1lZUuC0g2N930WTSOhmmjQ20ysM5/6Jb+uGDTjHAc6h56SVnv
wyJp8VxHq+itWNGtNmtxplYiR0z8UIiT+0LGmHN9+m6iFGW+TK78epVV/wDCzphqtaU1QV2xQrSnnfPp9ao8ilpyVextzgbLbPQp
PdHaaJ90l0lS2Cts0O2PzsDwcOHPtG1Vpm1EJ5TWMg3tPDmPFeYetXD/AHJoXeUxQL3kwxMNguS0w1lTE6z3OtK+Uk+HVJ2Me6xV
mt4p2/jrB3HerdPBFKwTwG7feDwPAq00n1TctlqYodxSknWrfqeG5ym1FPNLzSR0Cu9Dg+S6nCkmM+pjfG4yw+sL1nAsRo8Zp2Yd
iRs5uTJBtbzHiOY5FZBqDw8S1Roc5d+i7szWaBKALqlJewqo0PP6skforPg8gfsgDFylxFsjb32bebp7fgsLHNE5qKpFNUN1Xu8l
w8iT+E7ncWHPhcKm0r4epm6KSu677m1W1Y8o8W1VBTYU/UXR1l5Js/orncVegjqTtiLFTiMccesTl+Nn4yWVhuiVTU1opI260pz1
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
]==]
    local function decodeEmbeddedJpg(payload)
        local alphabet='ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
        local codes={}
        for i=1,#alphabet do codes[alphabet:sub(i,i)]=i-1 end
        local s=payload:gsub('%s+','')
        if #s%4~=0 then return nil end
        local out, n={}, 0
        for i=1,#s,4 do
            local a,b,c,d=s:sub(i,i),s:sub(i+1,i+1),s:sub(i+2,i+2),s:sub(i+3,i+3)
            local x,y,z,w=codes[a],codes[b],c=='=' and 0 or codes[c],d=='=' and 0 or codes[d]
            if x==nil or y==nil or z==nil or w==nil then return nil end
            local v=x*262144+y*4096+z*64+w
            n=n+1
            if c=='=' then
                out[n]=string.char(math.floor(v/65536)%256)
            elseif d=='=' then
                out[n]=string.char(math.floor(v/65536)%256,math.floor(v/256)%256)
            else
                out[n]=string.char(math.floor(v/65536)%256,math.floor(v/256)%256,v%256)
            end
        end
        return table.concat(out)
    end
    local function embeddedTexture()
        if UI._embeddedTexture then return UI._embeddedTexture end
        if UI._embeddedTried then return nil end
        UI._embeddedTried=true
        local kr=imported('KismetRenderingLibrary') or imported('UKismetRenderingLibrary')
        if not kr then return nil end
        local getWorld=member(global('slua'),'getWorld')
        if type(getWorld)~='function' then return nil end
        local okWorld,world=pcall(getWorld)
        if not okWorld or not world then return nil end
        local data=decodeEmbeddedJpg(SHAYAN_EMBEDDED_PORTAL_JPG)
        if not data or #data<1000 then return nil end
        -- Prefer an in-memory import if this game exposes one; no disk file then.
        local fromMemory=member(kr,'ImportBufferAsTexture2D')
        if type(fromMemory)=='function' then
            local ok,tex=pcall(fromMemory,kr,world,data)
            if ok and tex then UI._embeddedTexture=tex return tex end
            ok,tex=pcall(fromMemory,world,data)
            if ok and tex then UI._embeddedTexture=tex return tex end
        end
        local fromFile=member(kr,'ImportFileAsTexture2D')
        if type(fromFile)~='function' then return nil end
        -- Cache generated by this single Lua itself: NO user-supplied PNG/JPG required.
        -- Some Android versions restrict local writes; fallback UMG is still available.
        local paths={}
        local temp=type(os)=='table' and type(os.getenv)=='function' and os.getenv('TMPDIR')
        if type(temp)=='string' and #temp>0 then paths[#paths+1]=temp..'/shayan_portal_v17.jpg' end
        paths[#paths+1]='/storage/emulated/0/Download/.shayan_portal_v17.jpg'
        paths[#paths+1]='/sdcard/Download/.shayan_portal_v17.jpg'
        if type(io)~='table' or type(io.open)~='function' then return nil end
        for i=1,#paths do
            local filepath=paths[i]
            local wrote=pcall(function()
                local f=assert(io.open(filepath,'wb'))
                assert(f:write(data))
                f:close()
            end)
            if wrote then
                local ok,tex=pcall(fromFile,kr,world,filepath)
                if not ok or not tex then ok,tex=pcall(fromFile,world,filepath) end
                if ok and tex then UI._embeddedTexture=tex return tex end
            end
        end
        return nil
    end
    local function detach(data)
        if not data then return end
        data.visible = false
        pcall(function() if valid(data.input) then data.input:SetText("") end end)
        if data.event and data.eventHandle ~= nil then
            pcall(function() data.event:Remove(data.eventHandle) end)
        end
        if valid(data.container) then
            pcall(function() data.container:RemoveFromParent() end)
        end
        if valid(data.modalBlocker) then
            pcall(function() data.modalBlocker:RemoveFromParent() end)
        end
        data.onSubmit = nil
    end
    function UI.Destroy()
        local previous = UI._data
        UI._data = nil
        detach(previous)
    end
    function UI.Hide()
        local data = UI._data
        if not data or data.hiddenApplied then return true end
        data.visible = false
        local ok = pcall(function()
            if valid(data.input) then data.input:SetText("") end
            if valid(data.container) then visibility(data.container, data.hidden) end
            if valid(data.modalBlocker) then visibility(data.modalBlocker, data.hidden) end
        end)
        if ok then data.hiddenApplied = true end
        return ok
    end
    function UI.SetStatus(message)
        UI._status = type(message) == "string" and message:sub(1, 160) or "Login unavailable"
        local data = UI._data
        if data and data.deliveredStatus == UI._status then return true end
        if data and valid(data.status) then
            local ok = pcall(function() data.status:SetText(UI._status) end)
            if ok then data.deliveredStatus = UI._status end
            return ok
        end
        return false
    end
    function UI.SetBusy(busy)
        UI._busy = busy == true
        local data = UI._data
        if data then
            if data.deliveredBusy == UI._busy then return true end
            local buttonOK = pcall(function() data.button:SetIsEnabled(not UI._busy) end)
            local inputOK = pcall(function() data.input:SetIsEnabled(not UI._busy) end)
            if buttonOK and inputOK then
                data.deliveredBusy = UI._busy
                return true
            end
        end
        return false
    end
    function UI.Animate(now)
        local data=UI._data
        if not data or not data.visible or type(now)~='number' then return false end
        if UI._lastAnimateAt and now-UI._lastAnimateAt<0.30 then return true end
        UI._lastAnimateAt=now
        if data.usingArt then return true end  -- artwork is a static texture, no per-frame refresh
        local glow=0.66+0.30*(0.5+0.5*math.sin(now*1.2))
        pcall(function()
            if valid(data.buttonGlow) then
                data.buttonGlow:SetBrushColor(color(1.0,0.93,0.31,glow))
            end
        end)
        return true
    end
    local function fitScale(parent)
        local result = 1
        pcall(function()
            local size = parent:GetCachedGeometry():GetLocalSize()
            local width, height = size.X, size.Y
            if type(width) == 'number' and type(height) == 'number' and width > 24 and height > 24 then
                result = math.min(1, (width - 32) / 720, (height - 32) / 520)
            end
        end)
        return result
    end
    function UI.Show(onSubmit)
        if type(onSubmit) ~= "function" then return false, "UI_SUBMIT_REQUIRED" end
        local okTools, uiTools = pcall(require, "GameLua.Mod.BaseMod.Common.UI.InGameUITools")
        local getRoot = okTools and member(uiTools, "GetMainControlBaseUI")
        if type(getRoot) ~= "function" then return false, "UI_NOT_READY" end
        local okRoot, root = pcall(getRoot)
        if not okRoot or not valid(root) then return false, "UI_NOT_READY" end
        -- Always resolve the current canvas. Old cached widgets may belong to a prior map.
        local parent = member(root, "CanvasPanel_42")
        if not valid(parent) then parent = member(root, "CanvasPanel_0") end
        if not valid(parent) then return false, "UI_NOT_READY" end
        local data = UI._data
        if data and (data.parent ~= parent or
            math.abs(fitScale(parent) - (data.scale or 1)) > 0.001) then
            UI.Destroy()
            data = nil
        end
        if data and valid(data.container) and valid(data.parent) then
            local ok = data.visible or pcall(function()
                visibility(data.modalBlocker, data.visibleEnum)
                visibility(data.container, data.passiveEnum or data.visibleEnum)
            end)
            if ok then
                data.onSubmit, data.visible, data.hiddenApplied = onSubmit, true, false
                UI.SetStatus(UI._status)
                UI.SetBusy(UI._busy)
                return true
            end
        end
        UI.Destroy()
        local game = global("CGame")
        if type(member(game, "NewObjectFromPath")) ~= "function" then return false, "UI_FACTORY_UNAVAILABLE" end
        local enums = member(global("UEnums"), "ESlateVisibility")
        local visibleEnum, hidden = member(enums, "Visible"), member(enums, "Collapsed")
        local passive = member(enums, "SelfHitTestInvisible")
        if visibleEnum == nil or hidden == nil or passive == nil then return false, "UI_ENUM_UNAVAILABLE" end
        UI._scale = fitScale(parent)
        data = {
            parent = parent, visible = false, onSubmit = onSubmit,
            visibleEnum = visibleEnum, passiveEnum = passive, hidden = hidden, scale = UI._scale
        }
        local okBuild = pcall(function()
            local function make(class, outer)
                local widget = game:NewObjectFromPath("/Script/UMG." .. class, outer)
                assert(valid(widget), "UI_WIDGET_UNAVAILABLE")
                local clip = member(member(global('UEnums'), 'EWidgetClipping'), 'ClipToBounds')
                if clip ~= nil then pcall(function() widget:SetClipping(clip) end) end
                return widget
            end

            local W, H = 720, 520

            -- Login-only modal layer:
            -- blocks the game's touch/UI controls from sitting on top of the login panel.
            data.modalBlocker = make("Border", parent)
            data.modalBlocker:SetBrushColor(color(0, 0, 0, 0))
            visibility(data.modalBlocker, visibleEnum)
            local modalSlot = parent:AddChildToCanvas(data.modalBlocker)
            assert(valid(modalSlot), "UI_MODAL_SLOT_UNAVAILABLE")
            modalSlot:SetAutoSize(false)
            modalSlot:SetPosition(vector(0, 0))
            pcall(function()
                local parentSize = parent:GetCachedGeometry():GetLocalSize()
                if parentSize and parentSize.X and parentSize.Y and parentSize.X > 24 and parentSize.Y > 24 then
                    modalSlot:SetSize(vector(parentSize.X, parentSize.Y))
                else
                    modalSlot:SetSize(vector(4096, 4096))
                end
            end)
            modalSlot:SetZOrder(100000)
            data.modalSlot = modalSlot

            data.container = make("CanvasPanel", parent)

            local function add(widget, x, y, width, height, z)
                local slot = data.container:AddChildToCanvas(widget)
                assert(valid(slot), "UI_SLOT_UNAVAILABLE")
                slot:SetAutoSize(false)
                slot:SetPosition(vector(x * UI._scale, y * UI._scale))
                slot:SetSize(vector(width * UI._scale, height * UI._scale))
                slot:SetZOrder(z)
                return slot
            end

            local function text(class, value, size, r, g, b, a)
                local w = make(class, data.container)
                w:SetText(value)
                setTextStyle(w, size, color(r, g, b, a or 1))
                visibility(w, passive)
                return w
            end

            -- SHAYAN V17: embedded image plus native fallback (one file, no external asset).
            -- Design canvas: 720 x 520. All decorative widgets are hit-test invisible.
            -- Input, button and authentication callbacks are real interactive widgets.
            local function plate(x,y,w,h,r,g,b,a,z,field)
                local wdg=make('Border',data.container)
                wdg:SetBrushColor(color(r,g,b,a or 1))
                visibility(wdg,passive)
                add(wdg,x,y,w,h,z or 2)
                if field then data[field]=wdg end
                return wdg
            end
            local function caption(value,size,x,y,w,h,r,g,b,z)
                local wdg=text('TextBlock',value,size,r,g,b)
                pcall(function()
                    local just=member(member(global('UEnums'),'ETextJustify'),'Center')
                    if just then wdg:SetJustification(just) end
                end)
                add(wdg,x,y,w,h,z or 13)
                return wdg
            end
            local function hline(x,y,w,h,r,g,b,z)
                return plate(x,y,w,h,r,g,b,1,z or 7)
            end
            -- V17 built-in artwork branch: exact SHAYAN red/gold/green design.
            local usingArt = false
            local artTexture = embeddedTexture()
            if artTexture then
                local ok = pcall(function()
                    local imageWidget = make('Image',data.container)
                    imageWidget:SetBrushFromTexture(artTexture, false)
                    visibility(imageWidget,passive)
                    add(imageWidget,0,0,W,H,6)
                    data.embeddedArtImage=imageWidget
                end)
                usingArt=ok
            end
            data.usingArt=usingArt
            if usingArt then
                -- Coordinates overlay the REAL editable field and clickable action onto
                -- the artwork; the image is NEVER used to fake a login response.
                data.input=make('EditableTextBox',data.container)
                assert(type(member(data.input,'GetText'))=='function','UI_INPUT_UNAVAILABLE')
                data.input:SetText('')
                setTextStyle(data.input,20,color(0.13,0.12,0.14,1))
                pcall(function() data.input:SetHintText('ENTER YOUR ACCESS KEY') end)
                pcall(function() data.input:SetIsReadOnly(false) end)
                pcall(function() data.input:SetIsPassword(false) end)
                local enums=global('UEnums')
                local keyType=member(member(enums,'EVirtualKeyboardType'),'Default')
                local trigger=member(member(enums,'EVirtualKeyboardTrigger'),'OnAllFocusEvents')
                if keyType~=nil then pcall(function() data.input.KeyboardType=keyType end) end
                if trigger~=nil then pcall(function() data.input.VirtualKeyboardTrigger=trigger end) end
                visibility(data.input,visibleEnum)
                add(data.input,116,308,490,34,23)
                pcall(function() data.input:SetIsEnabled(true) end)

                data.button=make('Button',data.container)
                visibility(data.button,visibleEnum)
                pcall(function() data.button:SetBackgroundColor(color(1,1,1,0.005)) end)
                add(data.button,133,362,454,56,24)
                pcall(function() data.button:SetIsEnabled(true) end)

                -- Status text overlays the ART'S blank black status strip.
                data.statusDot=plate(85,463,9,9,0.98,0.11,0.29,1,25)
                data.status=caption(UI._status,13,101,452,520,32,0.99,0.95,0.90,26)
                data.deliveredStatus=UI._status
            else
                -- Whole card is inside the centered canvas (no negative offsets or
                -- text/crown floating above the card as in V15).
                plate(7,8,706,506,0,0,0,0.52,0)
                plate(0,0,720,520,0.96,0.68,0.09,1,1)
                plate(3,3,714,514,0.025,0.027,0.035,1,2)
                plate(8,8,704,504,0.042,0.046,0.060,1,3)
                -- Symmetric crimson and emerald edges, with restrained golden accents.
                hline(5,5,352,5,0.96,0.08,0.13)
                hline(363,5,352,5,0.04,0.93,0.28)
                hline(5,510,352,5,0.97,0.10,0.14)
                hline(363,510,352,5,0.04,0.93,0.28)
                hline(5,11,5,495,0.86,0.08,0.12)
                hline(710,11,5,495,0.04,0.80,0.25)
                plate(13,16,694,119,0.055,0.056,0.073,1,5)
                hline(25,130,670,2,0.96,0.72,0.16)
                hline(35,136,135,2,0.90,0.10,0.15)
                hline(550,136,135,2,0.08,0.83,0.29)
                -- Crown badge is a text-only asset-free motif, not an external emoji glyph.
                plate(327,15,66,22,0.25,0.16,0.035,1,8)
                hline(331,17,58,2,0.98,0.79,0.11)
                caption('VIP',13,342,19,37,18,1,0.84,0.29,15)
                -- Fixed-width title placement, correct even if UMG justification is ignored.
                caption('SHAYAN',55,252,42,222,68,0.66,0.06,0.09,10)
                caption('SHAYAN',55,249,39,222,68,0.99,0.97,0.95,15)
                caption('@SHAYAN_OWNER',15,286,104,181,24,0.98,0.78,0.30,15)
                -- Distinct portal header strip.
                plate(34,150,652,83,0.27,0.18,0.042,1,5)
                plate(37,153,646,77,0.17,0.125,0.05,1,6)
                hline(36,151,648,3,0.98,0.76,0.10)
                hline(36,229,648,2,0.91,0.48,0.07)
                hline(38,165,5,51,0.99,0.80,0.19)
                hline(677,165,5,51,0.99,0.80,0.19)
                caption('VIP SYSTEM PORTAL',33,175,162,390,44,1,0.84,0.18,15)
                caption('P R E M I U M   A C C E S S',11,237,205,265,20,0.93,0.92,0.91,15)
                caption('ACCESS KEY',17,66,245,200,27,1,0.93,0.75,15)
                -- Key field: solid gold frame and readable editable text box.
                plate(65,275,590,60,0.98,0.76,0.09,1,7)
                plate(70,280,580,50,0.95,0.95,0.97,1,8)
                data.input=make('EditableTextBox',data.container)
                assert(type(member(data.input,'GetText'))=='function','UI_INPUT_UNAVAILABLE')
                data.input:SetText('')
                setTextStyle(data.input,21,color(0.11,0.10,0.13,1))
                pcall(function() data.input:SetHintText('ENTER YOUR ACCESS KEY') end)
                pcall(function() data.input:SetIsReadOnly(false) end)
                pcall(function() data.input:SetIsPassword(false) end)
                local enums=global('UEnums')
                local keyType=member(member(enums,'EVirtualKeyboardType'),'Default')
                local trigger=member(member(enums,'EVirtualKeyboardTrigger'),'OnAllFocusEvents')
                if keyType~=nil then pcall(function() data.input.KeyboardType=keyType end) end
                if trigger~=nil then pcall(function() data.input.VirtualKeyboardTrigger=trigger end) end
                visibility(data.input,visibleEnum)
                add(data.input,82,284,554,42,23)
                pcall(function() data.input:SetIsEnabled(true) end)
                -- Reference-inspired two-tone beveled authentication button.
                plate(115,357,490,70,0.05,0.80,0.19,1,7)
                plate(111,354,490,68,0.99,0.80,0.10,1,8)
                plate(118,361,476,54,0.94,0.65,0.03,1,9)
                data.buttonGlow=plate(118,361,476,4,0.99,0.92,0.33,1,10)
                caption('AUTHENTICATE NOW   >>',25,206,377,337,35,0.12,0.095,0.025,16)
                data.button=make('Button',data.container)
                visibility(data.button,visibleEnum)
                pcall(function() data.button:SetBackgroundColor(color(1,1,1,0.004)) end)
                add(data.button,118,361,476,54,24)
                pcall(function() data.button:SetIsEnabled(true) end)
                -- Status area is real runtime feedback, never a pre-rendered fake message.
                plate(83,436,554,42,0.065,0.067,0.080,1,6)
                data.statusDot=plate(99,452,9,9,0.98,0.11,0.29,1,10)
                data.status=caption(UI._status,14,117,442,498,29,0.98,0.97,0.94,17)
                data.deliveredStatus=UI._status
                hline(35,484,650,2,0.85,0.62,0.12)
                caption('SHAYAN   |   @SHAYAN_OWNER   |   PREMIUM ACCESS',11,
                        166,489,390,21,0.97,0.83,0.36,15)
            end
            data.event = data.button.OnClicked
            assert(type(member(data.event, "Add")) == "function", "UI_BUTTON_UNAVAILABLE")
            data.eventHandle = data.event:Add(function()
                if UI._data ~= data or not data.visible or UI._busy then return end
                local readOK, key = pcall(function() return data.input:GetText() end)
                if not readOK or type(key) ~= "string" then
                    UI.SetStatus("Unable to read the access key")
                    return
                end
                key = key:match("^%s*(.-)%s*$")
                if key == "" or #key > 512 then
                    UI.SetStatus("Enter a valid access key")
                    return
                end
                local submitOK = pcall(data.onSubmit, key)
                if not submitOK then
                    UI.SetBusy(false)
                    UI.SetStatus("Login could not start")
                end
            end)

            local slot = parent:AddChildToCanvas(data.container)
            assert(valid(slot), "UI_SLOT_UNAVAILABLE")
            slot:SetAutoSize(false)
            slot:SetSize(vector(W * UI._scale, H * UI._scale))
            -- Keep the login panel above the modal blocker and normal game HUD.
            slot:SetZOrder(100001)
            local anchors = slot:GetAnchors()
            anchors.Minimum, anchors.Maximum = vector(0.5, 0.5), vector(0.5, 0.5)
            slot:SetAnchors(anchors)
            slot:SetAlignment(vector(0.5, 0.5))
            slot:SetPosition(vector(0, 0))
            visibility(data.modalBlocker, visibleEnum)
            -- Container itself is transparent to hit-testing; Button/EditBox children
            -- remain interactive while the full-screen blocker prevents HUD touches.
            visibility(data.container, passive)
        end)
        if not okBuild then
            detach(data)
            return false, "UI_BUILD_UNAVAILABLE"
        end
        data.visible = true
        UI._data = data
        UI.SetBusy(UI._busy)
        return true
    end
    function UI.ShowNotice(message)
        local shown, reason = UI.Show(function() return false end)
        if not shown then return false, reason end
        UI.SetStatus(message)
        UI.SetBusy(true)
        return true
    end
    return UI
end
return Module
end)()

-- ========================================================================
-- 11. LOGIN HOST AND SESSION
-- ========================================================================

local ShayanLicenseRuntime = (function()
local Runtime = {}
Runtime.__index = Runtime
local function finite(n) return type(n) == 'number' and n == n and n >= 0 and n < math.huge end
local function read(o, k)
    if o == nil then return nil end
    local ok, v = pcall(function() return o[k] end)
    if ok then return v end
end
local function static(o, k, ...)
    local fn = read(o, k)
    if type(fn) ~= 'function' then return nil end
    local ok, v = pcall(fn, ...)
    if ok then return v end
end
local function call(o, k, ...)
    local fn = read(o, k)
    if type(fn) ~= 'function' then return nil end
    local ok, v = pcall(fn, o, ...)
    if ok then return v end
end
local function validConfig(c)
    return type(c) == 'table' and type(c.url) == 'string' and c.url:match('^https://') ~= nil
        and type(c.game) == 'string' and #c.game > 0
        and finite(c.timeout) and c.timeout > 0 and finite(c.clockSkew)
end
function Runtime.new(env, config, Core, LoginUI)
    local self = setmetatable({
        env = env or _G, reason = 'login_required', active = false,
        ready = false, disposed = false, uiRetryAt = 0, uiFailures = 0
    }, Runtime)
    if not validConfig(config) or type(Core) ~= 'table' or type(Core.new) ~= 'function'
        or type(Core.Primitives) ~= 'table' then
        self.reason = 'license_dependencies_unavailable'
        return self
    end
    local cfg = {}
    for k, v in pairs(config) do cfg[k] = v end
    self.timeout = cfg.timeout
    if type(LoginUI) == 'table' and type(LoginUI.new) == 'function' then
        local ok, ui = pcall(LoginUI.new, self.env)
        if ok and type(ui) == 'table' then self.ui = ui end
    end
    self.submit = function(key) return self:login(key) end
    self._sessionRestoreTried = false
    local function postHttp(url, headers, body, callback, timeout)
        local manager = read(self.env, 'ModuleManager')
        local moduleConfig = read(manager, 'CommonModuleConfig')
        local getter = read(manager, 'GetModule')
        assert(type(getter) == 'function' and moduleConfig, 'HTTP_MANAGER_UNAVAILABLE')
        local moduleId = read(moduleConfig, 'http_manager')
        local okModule, http = pcall(getter, moduleId)
        if not okModule or not http then
            okModule, http = pcall(getter, manager, moduleId)
        end
        assert(okModule and http, 'HTTP_MODULE_UNAVAILABLE')
        local post = read(http, 'Post')
        assert(type(post) == 'function', 'HTTP_POST_UNAVAILABLE')
        local function onResponse(a, b)
            local success, payload = false, b
            if type(a) == 'boolean' then
                success = a
            elseif type(a) == 'number' then
                success = a >= 200 and a < 300
            elseif type(a) == 'table' then
                local status = read(a, 'statusCode') or read(a, 'code') or read(a, 'status')
                success = type(status) == 'number' and status >= 200 and status < 300
                payload = read(a, 'body') or read(a, 'data') or b
            end
            if type(payload) ~= 'string' then payload = nil end
            return callback(success, payload)
        end
        return post(http, url, headers, body, nil, onResponse, timeout)
    end
    local ok, auth = pcall(Core.new, cfg, {
        clock = function() return self:_clock() end,
        wall = function()
            local value = static(read(self.env, 'os'), 'time')
            if finite(value) and value > 0 then return value end
        end,
        serial = function(key)
            local client = read(self.env, 'Client')
            local value = static(client, 'GetPhoneDeviceID')
            assert(type(value) == 'string' and #value > 0 and #value <= 512, 'DEVICE_ID_UNAVAILABLE')
            return Core.Primitives.name_uuid('Shayan-LUA-V1\0' .. key .. '\0' .. value)
        end,
        decode = function(raw)
            local json = self:_module('json', nil, 'common.json_util', 'decode')
            assert(json, 'JSON_UNAVAILABLE')
            return json.decode(raw)
        end,
        post = postHttp,
        feedback = function(event, key)
            if type(cfg.feedbackUrl) ~= 'string' or cfg.feedbackUrl == ''
                or cfg.feedbackUrl == 'PASTE_YOUR_BOT_FEEDBACK_URL_HERE' then
                return false
            end
            local hash = type(key) == 'string' and Core.Primitives.md5(key) or ''
            local wall = static(read(self.env, 'os'), 'time') or 0
            local body = 'game=' .. Core.Primitives.form_encode(cfg.game)
                .. '&event=' .. Core.Primitives.form_encode(tostring(event or 'unknown'))
                .. '&key_hash=' .. Core.Primitives.form_encode(hash)
                .. '&time=' .. Core.Primitives.form_encode(tostring(wall))
            local headers = { ['Content-Type'] = 'application/x-www-form-urlencoded' }
            if type(cfg.feedbackToken) == 'string' and #cfg.feedbackToken > 0
                and cfg.feedbackToken ~= 'PASTE_YOUR_BOT_TOKEN_HERE' then
                headers['Authorization'] = 'Bearer ' .. cfg.feedbackToken
            end
            return pcall(postHttp, cfg.feedbackUrl, headers, body, function() end, 5)
        end,
        status = function(message, phase)
            self.active = false
            self.reason = phase == 'active' and 'waiting_maintenance' or 'login_required'
            self:_ui('SetStatus', message)
            self:_ui('SetBusy', phase == 'pending')
            if phase == 'active' then self:_ui('Hide') end
        end
    })
    if ok and type(auth) == 'table' then self.auth = auth
    else self.reason = 'license_initialization_unavailable' end
    return self
end
function Runtime:_module(cache, globalName, path, method)
    local found = globalName and read(self.env, globalName)
    if type(read(found, method)) == 'function' then return found end
    found = self[cache]
    if type(read(found, method)) == 'function' then return found end
    local loader = read(self.env, 'require')
    if type(loader) == 'function' then
        local ok, value = pcall(loader, path)
        if ok and type(read(value, method)) == 'function' then
            self[cache] = value
            return value
        end
    end
end
function Runtime:_valid(object)
    if object == nil then return false end
    if static(read(self.env, 'slua'), 'isValid', object) == true then return true end
    return call(read(self.env, 'Game'), 'IsValid', object) == true
end
function Runtime:_clock()
    local world = static(read(self.env, 'slua'), 'getWorld')
    if world == nil then return nil end
    local statics = read(self.env, 'GameplayStatics') or self.statics
    if type(read(statics, 'GetRealTimeSeconds')) ~= 'function' then
        local loader = read(self.env, 'import')
        if type(loader) == 'function' then
            local ok, value = pcall(loader, 'GameplayStatics')
            if ok then statics = value end
        end
    end
    if type(read(statics, 'GetRealTimeSeconds')) ~= 'function' then return nil end
    self.statics = statics
    local now = static(statics, 'GetRealTimeSeconds', world)
    if finite(now) then return now, world end
end
function Runtime:_readGameplay(world)
    local data = read(self.env, 'GameplayData') or self.gameplayData
    if data == nil then
        local loader = read(self.env, 'require')
        if type(loader) == 'function' then
            local ok, value = pcall(loader, 'GameLua.GameCore.Data.GameplayData')
            if ok and value ~= nil then
                self.gameplayData = value
                data = value
            end
        end
    end
    local pc = static(data, 'GetPlayerController')
    if not self:_valid(pc) and not self:_valid(read(pc, 'Object')) then
        pc = call(read(self.env, 'slua_GameFrontendHUD'), 'GetPlayerController')
    end
    if not self:_valid(pc) and not self:_valid(read(pc, 'Object')) then return nil, 'waiting_controller' end
    local pawn = static(data, 'GetPlayerCharacter')
    if not self:_valid(pawn) then pawn = static(data, 'GetLocalCharacter') end
    for _, method in ipairs({ 'GetPlayerCharacterSafety', 'GetCurPawn', 'GetPawn' }) do
        if not self:_valid(pawn) then pawn = call(pc, method) end
        if not self:_valid(pawn) then pawn = call(read(pc, 'Object'), method) end
    end
    if not self:_valid(pawn) then return nil, 'waiting_pawn' end
    local tools = self:_module('tools', nil, 'GameLua.Mod.BaseMod.Common.UI.InGameUITools', 'GetMainControlBaseUI')
    local root = static(tools, 'GetMainControlBaseUI')
    if not self:_valid(root) then return nil, 'waiting_control_ui' end
    local status = self:_module('gameStatus', 'GameStatus', 'client.common.game_status', 'IsInFightingStatus')
    local loading = self:_module('loading', nil, 'client.slua.logic.loading.logic_loading', 'IsShowing')
    if not status or not loading then return nil, 'readiness_services_unavailable' end
    if static(status, 'IsInFightingStatus') ~= true then return nil, 'waiting_gameplay' end
    if static(loading, 'IsShowing') ~= false then return nil, 'waiting_loading' end
    return { world = world, controller = pc, pawn = pawn, root = root }
end
local function same(a, b)
    return a and b and a.world == b.world and a.controller == b.controller and a.pawn == b.pawn and a.root == b.root
end
function Runtime:_ui(method, ...)
    local fn = read(self.ui, method)
    if type(fn) ~= 'function' then return false, 'UI_UNAVAILABLE' end
    local ok, value, reason = pcall(fn, ...)
    if not ok then return false, 'UI_TEMPORARILY_UNAVAILABLE' end
    return value, reason
end
function Runtime:_clearReadiness(reason)
    self.active, self.ready = false, false
    self.identity, self.readySince, self.maintenanceAt, self.maintenanceWorld = nil, nil, nil, nil
    self.reason = reason
    self:_ui('Hide')
end
function Runtime:_showPanel(now, state, blocked)
    if now < self.uiRetryAt then return false end
    local shown, uiReason
    if blocked then shown, uiReason = self:_ui('ShowNotice', state.message)
    else shown, uiReason = self:_ui('Show', self.submit) end
    if shown then
        self.uiRetryAt = now + 0.35
        self.uiFailures, self.uiError = 0, nil
        self:_ui('SetStatus', state.message)
        self:_ui('SetBusy', blocked or state.pending)
    else
        self.uiFailures = self.uiFailures + 1
        self.uiRetryAt = now + (self.uiFailures >= 10 and 5 or 1)
        self.uiError = type(uiReason) == 'string' and uiReason:match('^UI_[A-Z_]+$') or 'UI_UNAVAILABLE'
    end
    return shown == true
end
function Runtime:update()
    if self.disposed then self.reason = 'disposed' return false end
    if not self.auth then return false end
    local tickOK = pcall(self.auth.Tick)
    if not tickOK then
        self.auth.FailClosed('License maintenance unavailable.')
        self:_clearReadiness('license_maintenance_unavailable')
        return false
    end
    local now, world = self:_clock()
    if not now then self:_clearReadiness('clock_unavailable') return false end
    self:_ui('Animate', now)
    local ready, reason = self:_readGameplay(world)
    if not ready then self:_clearReadiness(reason) return false end
    if not same(self.identity, ready) or not self.readySince or now < self.readySince then
        self.identity, self.readySince = ready, now
        self.uiRetryAt, self.uiFailures, self.uiError = 0, 0, nil
        self:_ui('Destroy')
    end
    self.ready = now - self.readySince >= 0.25
    self.maintenanceAt, self.maintenanceWorld = now, world

    -- If the Lua module was reloaded during a new match but the game process
    -- is still alive, restore the in-memory session silently. This does not
    -- survive a fresh game process, so a full restart still requires login.
    if self.ready and not self.auth.IsAuthorized() and not self._sessionRestoreTried then
        self._sessionRestoreTried = true
        local cached
        pcall(function()
            local session = _G.__SHAYANSession
            if type(session) == 'table' and type(session.key) == 'string' and #session.key > 0 then
                cached = session.key
            end
        end)
        if cached then
            pcall(self.auth.Login, cached)
        end
    end

    self.active = self.ready and self.auth.IsAuthorized()
    if not self.ready then
        self.reason = 'waiting_stable_gameplay'
        self:_ui('Hide')
        return false
    end
    local state = self.auth.GetState()
    if self._sessionRestoreTried and not self.active and not state.pending then
        -- Cached session failed or expired; show the normal login panel.
        self._sessionRestoreTried = false
    end
    if self.active then
        self.reason = 'active'
        self:_ui('Hide')
        return true
    end
    self.reason = 'login_required'
    self:_showPanel(now, state, false)
    return false
end
function Runtime:isActive()
    if self.disposed or not self.auth or not self.active or not self.ready then return false end
    if not self.auth.IsAuthorized() then self.active = false return false end
    local now, world = self:_clock()
    if not now or world ~= self.maintenanceWorld or not self.maintenanceAt
        or now < self.maintenanceAt or now - self.maintenanceAt >= 3 then
        self.active = false
        self.reason = 'maintenance_stale'
        return false
    end
    return true
end
function Runtime:login(key)
    if self.disposed or not self.auth then return false end
    if self.auth.IsAuthorized() then return true end
    local now, world = self:_clock()
    if not self.ready or not now or world ~= self.maintenanceWorld or not self.maintenanceAt
        or now < self.maintenanceAt or now - self.maintenanceAt >= 0.25 then return false end
    local identity = self:_readGameplay(world)
    if not same(identity, self.identity) then
        self:_clearReadiness('waiting_stable_gameplay')
        return false
    end
    local ok, accepted = pcall(self.auth.Login, key)
    if not ok then
        self.auth.FailClosed('Login could not start.')
        return false
    end
    return accepted == true
end
function Runtime:getStatus()
    local active = self:isActive()
    local state = self.auth and self.auth.GetState() or {}
    return {
        authorized = active, sessionAuthorized = state.authorized == true,
        phase = state.phase or 'locked', message = state.message or 'License dependencies unavailable.',
        reason = self.reason, pending = state.pending == true, gameplayReady = self.ready,
        expiresAt = state.expiresAt, accessPolicy = 'game_session', expiryCheckPolicy = 'login_only',
        clockProtection = 'login_only', periodicRecheck = false, loginDelaySeconds = 0.25,
        restartRequired = state.restartRequired == true, uiError = self.uiError,
        lastRequestLatencyMs = state.lastRequestLatencyMs, latencyScope = 'license_http_round_trip',
        disposed = self.disposed
    }
end
function Runtime:logout()
    self.active = false
    if self.auth then self.auth.Logout() end
    self.reason = 'login_required'
    return true
end
function Runtime:dispose()
    if self.disposed then return true end
    self:logout()
    self.disposed = true
    self.ready = false
    self:_ui('Destroy')
    self.reason = 'disposed'
    self.submit = nil
    return true
end
return Runtime
end)()

-- ========================================================================
-- 12. ESP DATA AND TIMER LIFECYCLE
-- ========================================================================

local ShayanESPRuntime = (function()
local Runtime = {}
Runtime.__index = Runtime
local floor, abs, pi = math.floor, math.abs, math.pi
local function finite(v) return type(v) == 'number' and v == v and v > -math.huge and v < math.huge end
local function indexed(object, key) return object[key] end
local function read(object, key)
    if object == nil then return nil end
    local ok, value = pcall(indexed, object, key)
    if ok then return value end
end
local function call(object, key, ...)
    local fn = read(object, key)
    if type(fn) ~= 'function' then return nil end
    local ok, a, b, c = pcall(fn, object, ...)
    if ok then return a, b, c end
end
local function static(object, key, ...)
    local fn = read(object, key)
    if type(fn) ~= 'function' then return nil end
    local ok, a, b, c = pcall(fn, ...)
    if ok then return a, b, c end
end
local function point(v)
    local x, y, z = read(v, 'X'), read(v, 'Y'), read(v, 'Z')
    if finite(x) and finite(y) and finite(z) then return x, y, z end
end
local function point2(v)
    local x, y = read(v, 'X'), read(v, 'Y')
    if finite(x) and finite(y) then return x, y end
end
local function flag(v)
    if v == true or v == 1 then return true end
    if v == false or v == 0 then return false end
end
local function mergeFlag(a, b)
    b = flag(b)
    if a == true or b == true then return true end
    if a == false or b == false then return false end
end
local function id(v) return (finite(v) and v > 0) or (type(v) == 'string' and v ~= '') end
local function module(env, key, path, native)
    local value = env[key]
    if value ~= nil then return value end
    local loader = native and env.import or env.require
    if type(loader) == 'function' then
        local ok, result = pcall(loader, path)
        if ok then return result end
    end
end

function Runtime.new(HUD, UMGAdapter, env, VisualFeatures, AimFeatures, WeaponFeatures, license, BypassFeatures)
    assert(type(HUD) == 'table' and type(HUD.new) == 'function', 'HUD module required')
    assert(type(UMGAdapter) == 'table' and type(UMGAdapter.new) == 'function', 'UMG adapter required')
    env = env or _G
    local self = setmetatable({
        HUD = HUD, UMGAdapter = UMGAdapter, env = env, VisualFeatures = VisualFeatures, AimFeatures = AimFeatures,
        WeaponFeatures = WeaponFeatures,
        owner = nil, timer = nil, mode = nil, generation = 0, state = 'idle', lastError = nil,
        scheduledTicks = 0, nextSetupTick = 0, menuOnly = false, activePawn = nil,
        roster = {}, records = {}, snapshots = {}, player = {}, totalFrames = 0,
        rosterOverflow = 0, rosterOverflowUnknown = false, unknownActors = 0, projectionMissing = 0,
        nextRoster = 0, nextSetup = 0, nextGameStateLookup = 0, lastTime = nil, setupAttempts = 0,
        maxActors = 256, range = 300, settings = nil,
        -- Adaptive actor processing: avoid a full native actor/projection pass every frame
        -- when the lobby is crowded. Existing snapshots are reused between passes.
        actorPass = 0, actorPassInterval = 1, lastRosterSize = 0
    }, Runtime)
    self.license = license
    self.BypassFeatures = BypassFeatures
    self.gd = module(env, 'GameplayData', 'GameLua.GameCore.Data.GameplayData')
    self.cgs = module(env, 'CGameState', 'GameLua.GameCore.Data.CGameState')
    self.ui = module(env, 'InGameUITools', 'GameLua.Mod.BaseMod.Common.UI.InGameUITools')
    self.gs = module(env, 'UGameplayStatics', 'GameplayStatics', true)
    self.wll = module(env, 'WidgetLayoutLibrary', 'WidgetLayoutLibrary', true)
    self.sbl = module(env, 'SlateBlueprintLibrary', 'SlateBlueprintLibrary', true)
    self.healthStatus = module(env, 'ECharacterHealthStatus', 'ECharacterHealthStatus', true)
    self.vector2 = module(env, 'FVector2D', 'Vector2D', true)
    self.vector3 = module(env, 'FVector', 'Vector', true)
    self.toCanvas = function(x, y) return self:_toCanvas(x, y) end
    return self
end

function Runtime:_licenseAllows()
    if not self.license or type(self.license.isActive) ~= 'function' then return false end
    local ok, active = pcall(self.license.isActive, self.license)
    return ok and active == true
end

function Runtime:_valid(object)
    if object == nil then return false end
    local value = static(self.env.slua, 'isValid', object)
    if value == true then return true end
    return call(self.env.Game, 'IsValid', object) == true
end

function Runtime:_object(owner) return read(owner, 'Object') or owner end

function Runtime:_controller()
    if not self.gd then self.gd = module(self.env, 'GameplayData', 'GameLua.GameCore.Data.GameplayData') end
    local pc = static(self.gd, 'GetPlayerController')
    if self:_valid(pc) or self:_valid(self:_object(pc)) then return pc end
    pc = call(self.env.slua_GameFrontendHUD, 'GetPlayerController')
    if self:_valid(pc) or self:_valid(self:_object(pc)) then return pc end
end

function Runtime:_pawn(pc)
    local pawn = static(self.gd, 'GetPlayerCharacter')
    if self:_valid(pawn) then return pawn end
    pawn = static(self.gd, 'GetLocalCharacter')
    if self:_valid(pawn) then return pawn end
    pawn = call(pc, 'GetPlayerCharacterSafety')
    if self:_valid(pawn) then return pawn end
    pawn = call(pc, 'GetCurPawn')
    if self:_valid(pawn) then return pawn end
end

function Runtime:_playerState(actor)
    local state = call(actor, 'GetPlayerStateSafety')
    if self:_valid(state) then return state end
    state = call(actor, 'GetPlayerState')
    if self:_valid(state) then return state end
    state = read(actor, 'PlayerState')
    if self:_valid(state) then return state end
end

function Runtime:_key(actor, state)
    local key = call(actor, 'GetPlayerKey')
    if id(key) then return key end
    key = read(actor, 'PlayerKey')
    if id(key) then return key end
    key = read(state, 'PlayerKey')
    if id(key) then return key end
end

function Runtime:_team(actor, state)
    local team = call(actor, 'GetTeamID')
    if finite(team) or (type(team) == 'string' and team ~= '') then return team end
    team = call(state, 'GetTeamID')
    if finite(team) or (type(team) == 'string' and team ~= '') then return team end
    team = read(state, 'TeamID')
    if finite(team) or (type(team) == 'string' and team ~= '') then return team end
    team = read(actor, 'TeamID')
    if finite(team) or (type(team) == 'string' and team ~= '') then return team end
end

function Runtime:_location(actor)
    local location = call(actor, 'K2_GetActorLocation')
    local x, y, z = point(location)
    if x ~= nil then return location, x, y, z end
    location = call(self.env.Game, 'GetActorLocation', actor)
    x, y, z = point(location)
    if x ~= nil then return location, x, y, z end
end

function Runtime:_localController(pc)
    if not self.env.Client then
        local frontend = call(self.env.slua_GameFrontendHUD, 'GetPlayerController')
        if not self:_valid(frontend) and not self:_valid(self:_object(frontend)) then return false end
        return self:_object(pc) == self:_object(frontend), frontend
    end
    local current = self:_controller()
    return current ~= nil and self:_object(pc) == self:_object(current), current
end

function Runtime:_local(owner)
    if not self.env.Client or not self:_valid(self:_object(owner)) then return false end
    local controlled = call(owner, 'IsLocallyControlled')
    if controlled ~= true then controlled = call(owner, 'IsAutonomousProxy') end
    if controlled ~= true then return false end
    local localPawn = self:_pawn(self:_controller())
    if self:_valid(localPawn) then
        return self:_object(owner) == self:_object(localPawn)
    end
    return true
end

function Runtime:_time()
    local world = self.env.CGameWorld or (self.owner and self:_object(self.owner))
    local value = static(self.gs, 'GetTimeSeconds', world)
    if finite(value) and value >= 0 then return value end
end

function Runtime:_error(message)
    self.lastError = tostring(message or 'native operation unavailable'):sub(1, 240)
end

function Runtime:_releaseVisuals()
    if self.visuals then
        local ok, err = pcall(self.visuals.dispose, self.visuals)
        self.lastVisualStatus = call(self.visuals, 'getStatus')
        if not ok then self:_error(err) end
        self.visuals = nil
    end
    self.nextVisualStatus = nil
    self.visualStatusIpad, self.visualStatusWall = nil, nil
    self.visualStatusVisible, self.visualStatusOccluded = nil, nil
end
function Runtime:_syncVisuals(pawn, now)
    local settings = self.hud and self.hud.visual
    if not settings then return end
    if not self.visuals and (settings.ipadView or settings.wallHack) and self.VisualFeatures then
        local ok, value = pcall(self.VisualFeatures.new, self.env)
        if ok then self.visuals = value else self:_error(value) end
    end
    if self.visuals then
        local ok, err = pcall(self.visuals.update, self.visuals, pawn, self.snapshots, settings, now)
        if not ok then self:_error(err) self:_releaseVisuals() end
        local changed = self.visualStatusIpad ~= settings.ipadView or self.visualStatusWall ~= settings.wallHack or
            self.visualStatusVisible ~= settings.visibleColor or self.visualStatusOccluded ~= settings.occludedColor
        if self.visuals and type(self.hud.setFeatureStatus) == 'function' and
            (changed or not self.nextVisualStatus or now >= self.nextVisualStatus) then
            self.nextVisualStatus = now + 0.2
            self.visualStatusIpad, self.visualStatusWall = settings.ipadView, settings.wallHack
            self.visualStatusVisible, self.visualStatusOccluded = settings.visibleColor, settings.occludedColor
            local status = call(self.visuals, 'getStatus')
            if type(status) == 'table' then self.hud:setFeatureStatus(status) end
        end
    end
end

function Runtime:_aimEnabled()
    local settings = self.hud and self.hud.aim
    return self.AimFeatures ~= nil and settings ~= nil and
        (settings.force == true or settings.assistant == true or settings.mortar == true or settings.sniper == true)
end

function Runtime:_publishWeaponStatus(status)
    if type(status) == 'table' then self.lastWeaponStatus = status end
    if self.hud and self.lastWeaponStatus and type(self.hud.setWeaponStatus) == 'function' then
        self.hud:setWeaponStatus(self.lastWeaponStatus)
    end
end

function Runtime:_disposeWeapons()
    local ok, err = pcall(self.weapons.dispose, self.weapons)
    local status = call(self.weapons, 'getStatus')
    if not ok then self:_error(err) end
    local pending = not ok or type(status) ~= 'table' or (tonumber(status.pendingCleanup) or 0) > 0
    self.weaponRetiring = pending
    if pending then
        self.nextWeaponCleanup = self.lastTime and self.lastTime + 1 or nil
        self.nextWeaponCleanupTick = self.scheduledTicks + 50
    else
        self.weapons, self.nextWeaponCleanup, self.nextWeaponCleanupTick = nil, nil, nil
    end
    self:_publishWeaponStatus(status or { active = false, lastStatus = 'cleanup_status_unavailable', pendingCleanup = 1 })
end

function Runtime:_releaseWeapons()
    if self.weapons and not self.weaponRetiring then self:_disposeWeapons() end
    self.nextWeaponStatus = nil
end

function Runtime:_retryWeaponCleanup(now)
    if not self.weapons or not self.weaponRetiring then return end
    local due = now and self.nextWeaponCleanup and now >= self.nextWeaponCleanup
    if due or self.scheduledTicks >= (self.nextWeaponCleanupTick or math.huge) then self:_disposeWeapons() end
end

function Runtime:_syncWeapons(pawn, now)
    local settings = self.hud and self.hud.aim
    if not settings or settings.smallCrosshair ~= true then
        self:_releaseWeapons()
        self.nextWeaponSetup = nil
        return
    end
    if self.weaponRetiring then return end
    if not self.WeaponFeatures then
        self:_publishWeaponStatus({ active = false, lastStatus = 'module_unavailable', smallCrosshairSupported = false })
        return
    end
    if not self.weapons then
        if self.nextWeaponSetup and now < self.nextWeaponSetup then return end
        local ok, value = pcall(self.WeaponFeatures.new, self.env)
        if not ok or type(value) ~= 'table' then
            self:_error(ok and 'Weapon module constructor unavailable' or value)
            self.nextWeaponSetup = now + 1
            self:_publishWeaponStatus({ active = false, lastStatus = 'runtime_constructor_failed' })
            return
        end
        self.weapons = value
        self.nextWeaponSetup = nil
    end
    local ok, err = pcall(self.weapons.update, self.weapons, pawn, settings, now)
    if not ok then
        self:_error(err)
        self:_releaseWeapons()
        self.nextWeaponSetup = now + 1
        local status = self.lastWeaponStatus or {}
        status.lastStatus = 'runtime_update_failed'
        self:_publishWeaponStatus(status)
        return
    end
    if not self.nextWeaponStatus or now >= self.nextWeaponStatus then
        self.nextWeaponStatus = now + 0.2
        self:_publishWeaponStatus(call(self.weapons, 'getStatus'))
    end
end

function Runtime:_publishBypassStatus(status)
    if type(status) == 'table' then self.lastBypassStatus = status end
    if self.hud and self.lastBypassStatus and type(self.hud.setBypassStatus) == 'function' then
        self.hud:setBypassStatus(self.lastBypassStatus)
    end
end

function Runtime:_disposeBypass()
    if not self.bypass then return end
    local ok = pcall(self.bypass.dispose, self.bypass)
    local status = call(self.bypass, 'getStatus')
    self.bypassRetiring = not ok or type(status) ~= 'table' or (tonumber(status.pendingCleanup) or 0) > 0
    self.nextBypassCleanup = self.lastTime and self.lastTime + 1 or nil
    if not self.bypassRetiring then self.bypass, self.nextBypassCleanup = nil, nil end
    self:_publishBypassStatus(status or { active = false, installedCount = 0, pendingCleanup = 1, lastStatus = 'cleanup_unavailable' })
end

function Runtime:_releaseBypass()
    if self.bypass and not self.bypassRetiring then self:_disposeBypass() end
    self.nextBypassStatus = nil
end

function Runtime:_syncBypass(now)
    local settings = self.hud and self.hud.aim
    if not settings then
        self:_releaseBypass()
        self.nextBypassSetup = nil
        return
    end
    settings.bypass = true
    if self.bypassRetiring then return end
    if not self.BypassFeatures then
        self:_publishBypassStatus({ active = false, installedCount = 0, lastStatus = 'module_unavailable' })
        return
    end
    if not self.bypass then
        if self.nextBypassSetup and now < self.nextBypassSetup then return end
        local ok, value = pcall(self.BypassFeatures.new, self.env)
        if not ok or type(value) ~= 'table' then
            self.nextBypassSetup = now + 1
            self:_publishBypassStatus({ active = false, installedCount = 0, lastStatus = 'constructor_unavailable' })
            return
        end
        self.bypass, self.nextBypassSetup = value, nil
    end
    local ok = pcall(self.bypass.update, self.bypass, settings, now)
    if not ok then
        self:_releaseBypass()
        self.nextBypassSetup = now + 1
        return
    end
    if not self.nextBypassStatus or now >= self.nextBypassStatus then
        self.nextBypassStatus = now + 1
        self:_publishBypassStatus(call(self.bypass, 'getStatus'))
    end
end

function Runtime:maintenance()
    if not self.weaponRetiring and not self.bypassRetiring then return end
    local now = self:_time()
    if not finite(now) then return end
    local previous = self.lastMaintenance or self.lastTime
    if previous and now < previous then
        self.nextWeaponCleanup, self.nextBypassCleanup = now, now
    end
    self.lastMaintenance = now
    self:_retryWeaponCleanup(now)
    if self.weaponRetiring and (not self.nextWeaponCleanup or self.nextWeaponCleanup <= now) then
        self.nextWeaponCleanup = now + 1
    end
    if self.bypassRetiring and (not self.nextBypassCleanup or now >= self.nextBypassCleanup) then
        self:_disposeBypass()
        if self.bypassRetiring then self.nextBypassCleanup = now + 1 end
    end
end

function Runtime:_aimWorld()
    local world = static(self.env.slua, 'getWorld')
    if self:_valid(world) then return world end
end

function Runtime:_releaseAim()
    if self.aims then
        local ok, err = pcall(self.aims.dispose, self.aims)
        self.lastAimStatus = call(self.aims, 'getStatus') or self.lastAimStatus
        if not ok then self:_error(err) end
    end
    self.aims, self.aimContext, self.nextAimStatus = nil, nil, nil
    self.aimStatusAssistant, self.aimStatusMortar, self.aimStatusSniper = nil, nil, nil
    self.aimStatusForce, self.aimIgnoreKnocked, self.aimIgnoreBots, self.aimVisibility = nil, nil, nil, nil
end

function Runtime:_aimUnavailable(reason)
    local status = self.lastAimStatus
    if type(status) ~= 'table' or status.lastStatus ~= reason then
        status = { lastStatus = reason, activeMode = nil, target = nil, nativeGameVerified = false, mortarPhysicsVerified = false }
        self.lastAimStatus = status
    end
    if self.hud and type(self.hud.setAimStatus) == 'function' then self.hud:setAimStatus(status) end
end

function Runtime:_aimCurrent(context, pc, pawn)
    if self.aimContext ~= context or self.generation ~= context.generation or self.owner == nil or
        self.timer == nil or self.menuOnly or not self.projectionCoordinates or self.lastTime ~= context.snapshotTime then return false end
    pc, pawn = pc or context.pc, pawn or context.pawn
    if self:_object(pc) ~= self:_object(context.pc) or self:_object(pawn) ~= self:_object(context.pawn) then return false end
    if self.activePawn == nil or self:_object(self.activePawn) ~= self:_object(pawn) then return false end
    local liveNow = self:_time()
    if not liveNow or liveNow < context.snapshotTime or liveNow - context.snapshotTime > 0.3 then return false end
    local current = self:_controller()
    if current == nil or self:_object(current) ~= self:_object(pc) then return false end
    if self.env.Client then
        if self.mode == 'controller' and self:_object(self.owner) ~= self:_object(current) then return false end
    else
        local frontend = call(self.env.slua_GameFrontendHUD, 'GetPlayerController')
        if not self:_valid(self:_object(frontend)) or self:_object(frontend) ~= self:_object(current) then return false end
    end
    local currentPawn = self:_pawn(current)
    if not self:_valid(currentPawn) or self:_object(currentPawn) ~= self:_object(pawn) then return false end
    return self:_aimWorld() == context.world
end

function Runtime:_syncAim(pc, pawn, now, snapshotWorld)
    local settings = self.hud and self.hud.aim
    if not settings or not self:_aimEnabled() then
        if self.aims then
            self:_releaseAim()
            if self.hud and self.lastAimStatus and type(self.hud.setAimStatus) == 'function' then self.hud:setAimStatus(self.lastAimStatus) end
        end
        self.nextAimSetup = nil
        return
    end
    if not finite(now) or not self.projectionCoordinates then
        self:_releaseAim()
        self:_aimUnavailable('context_unavailable')
        return
    end
    local world = self:_aimWorld()
    if world == nil or world ~= snapshotWorld then
        self:_releaseAim()
        self:_aimUnavailable(world == nil and 'world_unavailable' or 'context_changed')
        return
    end
    if self.aimContext and (self.aimContext.world ~= world or self.aimContext.pc ~= pc or self.aimContext.pawn ~= pawn) then
        self:_releaseAim()
    end
    if not self.aims then
        if self.nextAimSetup and now < self.nextAimSetup then return end
        local ok, value = pcall(self.AimFeatures.new, self.env)
        if not ok or type(value) ~= 'table' then
            self:_error(ok and 'Aim module constructor unavailable' or value)
            self:_aimUnavailable('runtime_constructor_failed')
            self.nextAimSetup = now + 1
            return
        end
        self.aims = value
        self.nextAimSetup = nil
    end
    local context = self.aimContext
    if not context then
        context = {}
        context.getWorld = function() return self:_aimWorld() end
        context.isCurrent = function(currentPC, currentPawn) return self:_aimCurrent(context, currentPC, currentPawn) end
        context.project = function(worldPoint, reuse)
            if self.aimContext ~= context or self.generation ~= context.generation or self.lastTime ~= context.snapshotTime then return nil, nil, reuse end
            return self:_project(context.pc, worldPoint, reuse)
        end
        self.aimContext = context
    end
    context.pc, context.pawn, context.world = pc, pawn, world
    context.width, context.height = self.width, self.height
    context.centerX, context.centerY = self.width / 2, self.height / 2
    context.radius = 105 * math.min(1.5, self.width / 1280, self.height / 720)
    context.snapshotTime, context.generation = now, self.generation
    if not context.isCurrent(pc, pawn) then
        self:_releaseAim()
        self:_aimUnavailable('context_changed')
        return
    end
    local ok, err = pcall(self.aims.update, self.aims, pc, pawn, self.snapshots, settings, now, context)
    if not ok then
        self:_error(err)
        self:_releaseAim()
        self:_aimUnavailable('runtime_update_failed')
        self.nextAimSetup = now + 1
        return
    end
    local changed = self.aimStatusAssistant ~= settings.assistant or self.aimStatusMortar ~= settings.mortar or
        self.aimStatusSniper ~= settings.sniper or self.aimStatusForce ~= settings.force or
        self.aimIgnoreKnocked ~= settings.ignoreKnocked or self.aimIgnoreBots ~= settings.ignoreBots or
        self.aimVisibility ~= settings.visibility
    if changed or not self.nextAimStatus or now >= self.nextAimStatus then
        self.nextAimStatus = now + 0.2
        self.aimStatusAssistant, self.aimStatusMortar, self.aimStatusSniper = settings.assistant, settings.mortar, settings.sniper
        self.aimStatusForce, self.aimIgnoreKnocked, self.aimIgnoreBots, self.aimVisibility = settings.force, settings.ignoreKnocked, settings.ignoreBots, settings.visibility
        self.lastAimStatus = call(self.aims, 'getStatus') or self.lastAimStatus
        if self.lastAimStatus and type(self.hud.setAimStatus) == 'function' then self.hud:setAimStatus(self.lastAimStatus) end
    end
end

function Runtime:_releaseUI()
    self:_releaseAim()
    self:_releaseWeapons()
    self:_releaseBypass()
    self:_releaseVisuals()
    if self.hud then
        local ok, saved = pcall(self.hud.exportSettings, self.hud)
        if ok and type(saved) == 'table' then self.settings = saved end
        pcall(self.hud.reset, self.hud)
    end
    if self.adapter then pcall(self.adapter.dispose, self.adapter) end
    self.hud, self.adapter, self.parent, self.geometry = nil, nil, nil, nil
    self.projectionCoordinates, self.scale = false, nil
    self.canvasXX, self.canvasXY, self.canvasYX, self.canvasYY = nil, nil, nil, nil
end

function Runtime:stop()
    local owner, handle = self.owner, self.timer
    self.generation = self.generation + 1
    self.owner, self.timer, self.mode, self.activePawn = nil, nil, nil, nil
    if owner and handle ~= nil then call(owner, 'RemoveGameTimer', handle) end
    self:_releaseUI()
    if (self.weaponRetiring or self.bypassRetiring) and finite(self.lastTime) then
        self.lastMaintenance = self.lastTime
    end
    self.roster, self.records, self.snapshots, self.player = {}, {}, {}, {}
    self.rosterOverflow, self.rosterOverflowUnknown, self.unknownActors, self.projectionMissing = 0, false, 0, 0
    self.lastTime, self.state, self.nextRoster, self.nextSetup = nil, 'idle', 0, 0
    self.nextGameStateLookup = 0
    self.scheduledTicks, self.nextSetupTick, self.menuOnly, self.dataState = 0, 0, false, nil
end

function Runtime:_clearSnapshots()
    self:_releaseBypass()
    self:_releaseAim()
    self:_releaseWeapons()
    self:_releaseVisuals()
    self.roster, self.records, self.snapshots, self.player = {}, {}, {}, {}
    self.rosterOverflow, self.rosterOverflowUnknown, self.unknownActors, self.projectionMissing = 0, false, 0, 0
    self.activePawn, self.nextRoster = nil, 0
    if self.hud then self.hud:reset() end
end

function Runtime:forget(owner)
    if self.mode == 'controller' then
        if self.activePawn and self:_object(owner) == self:_object(self.activePawn) then
            self:_clearSnapshots()
            self.menuOnly, self.dataState = true, 'waiting_local_player'
            return true
        end
        return false
    end
    if owner == self.owner then self:stop() return true end
    return false
end

function Runtime:forgetController(pc)
    if self.mode == 'controller' and self:_object(pc) == self:_object(self.owner) then
        self:stop()
        return true
    end
    return false
end

function Runtime:_deferSetup(now)
    self.nextSetup = now and now + 1 or nil
    self.nextSetupTick = self.scheduledTicks + 50
end

function Runtime:_start(owner, mode)
    if self.owner == owner and self.mode == mode and self.timer ~= nil then return true end
    self:stop()
    self.owner, self.mode = owner, mode
    local now = self:_time()
    self:_retryWeaponCleanup(now)
    if not now and mode ~= 'controller' then
        self.owner, self.mode, self.state = nil, nil, 'unsupported_clock'
        self:_error('GameplayStatics.GetTimeSeconds is unavailable; no substitute clock used')
        return false
    end
    if type(read(owner, 'AddGameTimer')) ~= 'function' or type(read(owner, 'RemoveGameTimer')) ~= 'function' then
        self.owner, self.mode, self.state = nil, nil, 'unsupported_timer'
        self:_error('Owner timer registration/removal is unavailable')
        return false
    end
    self.lastTime, self.nextSetup, self.state = now, now, 'waiting_ui'
    local generation = self.generation
    local callback = function()
        if self.generation ~= generation or self.owner ~= owner then return end
        self.scheduledTicks = self.scheduledTicks + 1
        local ok, err = pcall(self._step, self)
        if not ok then
            self:_error(err)
            self:_releaseUI()
            self:_deferSetup(self:_time())
            self.state = 'retrying_after_error'
        end
    end
    local ok, handle = pcall(owner.AddGameTimer, owner, 1/30, true, callback)
    if not ok or handle == nil then
        self:stop()
        self.state = 'unsupported_timer'
        self:_error(ok and 'AddGameTimer did not return a removable handle' or handle)
        return false
    end
    self.timer = handle
    return true
end

function Runtime:consider(owner)
    if not self:_licenseAllows() then return false end
    if not self:_local(owner) then return false end
    if self.mode == 'controller' and self.timer ~= nil and self:_localController(self.owner) then return true end
    return self:_start(owner, 'character')
end

function Runtime:considerController(pc)
    if not self:_licenseAllows() then return false end
    if not self:_localController(pc) then return false end
    return self:_start(pc, 'controller')
end

function Runtime:_vector2(x, y)
    if self.vector2 ~= nil then
        local ok, value = pcall(self.vector2, x, y)
        if ok and point2(value) ~= nil then return value end
        error('Vector2D constructor failed or returned invalid coordinates', 0)
    end
    return { X = x, Y = y }
end

function Runtime:_vector3(x, y, z)
    if self.vector3 ~= nil then
        local ok, value = pcall(self.vector3, x, y, z)
        if ok and point(value) ~= nil then return value end
        error('Vector constructor failed or returned invalid coordinates', 0)
    end
    return { X = x, Y = y, Z = z }
end

function Runtime:_setup(now)
    if now and self.nextSetup then
        if now < self.nextSetup then return false end
    elseif self.scheduledTicks < self.nextSetupTick then return false end
    self:_deferSetup(now)
    self.setupAttempts = self.setupAttempts + 1
    if not self.ui then
        self.ui = module(self.env, 'InGameUITools', 'GameLua.Mod.BaseMod.Common.UI.InGameUITools')
    end
    local ui = static(self.ui, 'GetMainControlBaseUI')
    if not self:_valid(ui) then self.state = 'waiting_ui' return false end
    local parent = read(ui, 'CanvasPanel_0')
    if not self:_valid(parent) then parent = read(ui, 'CanvasPanel_42') end
    if not self:_valid(parent) then self.state = 'waiting_canvas' return false end
    local ok, adapter, err = pcall(self.UMGAdapter.new, parent, self.env)
    if not ok or not adapter then
        self.state = 'unsupported_renderer'
        self:_error(ok and err or adapter)
        return false
    end
    self.adapter, self.parent = adapter, parent
    local config = { range = self.range, maxActors = self.maxActors }
    if self.settings then
        config.features = self.settings.features
        config.featureSets, config.style, config.visual = self.settings.featureSets, self.settings.style, self.settings.visual
        config.aim = self.settings.aim
        config.buttonX, config.buttonY = self.settings.buttonX, self.settings.buttonY
    end
    self.hud = self.HUD.new(adapter.renderer, config)
    self.nextRoster, self.state = 0, 'ready'
    return true
end

function Runtime:_transform(pc)
    local cache = self._transformCache
    if cache and cache.pc == pc and cache.width == self._lastVpW and cache.height == self._lastVpH then
        local now = self.lastTime or 0
        if cache.stamp and (now - cache.stamp) < 1.0 then
            return true
        end
    end
    self.geometry, self.scale = nil, nil
    self.canvasXX, self.canvasXY, self.canvasYX, self.canvasYY = nil, nil, nil, nil
    local viewport = self.viewportProbe or self:_vector2(0, 0)
    self.viewportProbe = viewport
    viewport.X, viewport.Y = 0, 0
    call(pc, 'GetViewportSize', viewport)
    local w, h = point2(viewport)
    if not w or w <= 0 or h <= 0 then
        viewport = static(self.wll, 'GetViewportSize', pc)
        w, h = point2(viewport)
    end
    self._lastVpW, self._lastVpH = w, h
    local geom = call(self.parent, 'GetCachedGeometry')
    self.projectionCoordinates = false
    if not w or w <= 0 or h <= 0 then
        local localSize = call(geom, 'GetLocalSize') or static(self.sbl, 'GetLocalSize', geom)
        local lw, lh = point2(localSize)
        if self.mode ~= 'controller' or not lw or lw <= 0 or lh <= 0 then
            return false, 'Viewport dimensions unavailable'
        end
        self.geometry, self.originX, self.originY, self.scale = nil, 0, 0, nil
        self.width, self.height = lw, lh
    else
        local origin, corner, horizontal
        if geom then
            self.canvasOriginProbe = self.canvasOriginProbe or self:_vector2(0, 0)
            self.canvasCornerProbe = self.canvasCornerProbe or self:_vector2(w, h)
            self.canvasHorizontalProbe = self.canvasHorizontalProbe or self:_vector2(w, 0)
            self.canvasOriginProbe.X, self.canvasOriginProbe.Y = 0, 0
            self.canvasCornerProbe.X, self.canvasCornerProbe.Y = w, h
            self.canvasHorizontalProbe.X, self.canvasHorizontalProbe.Y = w, 0
            origin = static(self.sbl, 'AbsoluteToLocal', geom, self.canvasOriginProbe)
            corner = static(self.sbl, 'AbsoluteToLocal', geom, self.canvasCornerProbe)
            horizontal = static(self.sbl, 'AbsoluteToLocal', geom, self.canvasHorizontalProbe)
        end
        local ox, oy = point2(origin)
        local ex, ey = point2(corner)
        local hx, hy = point2(horizontal)
        if ox and ex and hx then
            local xx, yx = (hx - ox) / w, (hy - oy) / w
            local xy, yy = (ex - hx) / h, (ey - hy) / h
            local determinant = xx * yy - xy * yx
            if not finite(determinant) or determinant == 0 or
                abs(determinant) <= 1e-12 * math.max(abs(xx * yy), abs(xy * yx)) then
                return false, 'Non-invertible canvas transform'
            end
            if ex <= ox or ey <= oy then return false, 'Canvas transform has unusable viewport bounds' end
            self.canvasXX, self.canvasXY, self.canvasYX, self.canvasYY = xx, xy, yx, yy
            self.geometry, self.originX, self.originY = geom, ox, oy
            self.width, self.height, self.scale = ex - ox, ey - oy, nil
        else
            local scale = static(self.wll, 'GetViewportScale', pc)
            if not finite(scale) or scale <= 0 then
                return false, 'Canvas transform and valid DPI scale unavailable'
            end
            self.geometry, self.originX, self.originY, self.scale = nil, 0, 0, scale
            self.width, self.height = w / scale, h / scale
        end
        self.projectionCoordinates = true
    end
    if type(self.adapter.setViewportOrigin) == 'function' then
        self.adapter:setViewportOrigin(self.originX, self.originY)
    elseif abs(self.originX) > 0.5 or abs(self.originY) > 0.5 then
        return false, 'Offset parent canvas needs adapter.setViewportOrigin'
    end
    self._transformCache = { pc = pc, stamp = self.lastTime or 0, width = w, height = h }
    return true
end

function Runtime:_toCanvas(x, y)
    if not finite(x) or not finite(y) then return nil end
    if self.geometry then
        if self.canvasXX == nil then return nil end
        local cx = self.canvasXX * x + self.canvasXY * y
        local cy = self.canvasYX * x + self.canvasYY * y
        if finite(cx) and finite(cy) then return cx, cy end
        return nil
    end
    if self.scale then return x / self.scale, y / self.scale end
end

function Runtime:_metadata(actor, record, now)
    if record.id ~= nil and type(record.isBot) == 'boolean' and record.team ~= nil and record.name ~= nil then
        return
    end
    local state = self:_playerState(actor)
    record.id = self:_key(actor, state)
    record.team = self:_team(actor, state)
    local name = call(actor, 'GetPlayerNameSafety')
    if type(name) ~= 'string' or name == '' then name = call(actor, 'GetPlayerName') end
    if type(name) ~= 'string' or name == '' then name = call(state, 'GetPlayerName') end
    if type(name) ~= 'string' or name == '' then name = read(state, 'PlayerName') end
    if type(name) ~= 'string' or name == '' then name = read(actor, 'PlayerName') end
    record.name = type(name) == 'string' and name or nil
    local bot = flag(call(self.env.Game, 'IsAI', actor))
    bot = mergeFlag(bot, read(actor, 'bIsAI'))
    bot = mergeFlag(bot, read(actor, 'IsAI'))
    bot = mergeFlag(bot, call(actor, 'IsBot'))
    if state then
        bot = mergeFlag(bot, read(state, 'bIsABot'))
        bot = mergeFlag(bot, read(state, 'bIsBot'))
        bot = mergeFlag(bot, read(state, 'bIsAI'))
        bot = mergeFlag(bot, call(state, 'IsBot'))
    end
    record.isBot = bot
    if not self:_valid(record.capsule) then
        local capsule = call(actor, 'GetCapsuleComponent') or read(actor, 'CapsuleComponent')
        record.capsule = self:_valid(capsule) and capsule or nil
    end
end

function Runtime:_roster(now)
    if now < self.nextRoster then return end
    -- Crowded lobbies do not need a full roster rebuild at 5 Hz. The current
    -- roster remains active between scans, so existing ESP features continue
    -- rendering while expensive enumeration is throttled.
    local scanInterval = (#self.roster > 48) and 0.35 or 0.20
    self.nextRoster = now + scanInterval
    local old = self.records
    local kept, roster, count, total, unknown = {}, self.roster, 0, 0, false
    local function take(actor)
        total = total + 1
        if total <= self.maxActors and self:_valid(actor) and not kept[actor] then
            count = count + 1
            roster[count] = actor
            kept[actor] = old[actor] or {}
        end
    end
    local function collect(pawns)
        if type(pawns) == 'table' then
            for _, actor in pairs(pawns) do
                take(actor)
                if total > self.maxActors then unknown = true break end
            end
        elseif pawns ~= nil and type(read(pawns, 'Num')) == 'function' and type(read(pawns, 'Get')) == 'function' then
            local n = call(pawns, 'Num')
            if finite(n) and n >= 0 then
                total = floor(n)
                for i = 0, math.min(total, self.maxActors) - 1 do
                    local actor = call(pawns, 'Get', i)
                    if self:_valid(actor) and not kept[actor] then
                        count = count + 1
                        roster[count] = actor
                        kept[actor] = old[actor] or {}
                    end
                end
            end
        else
            return false
        end
        return true
    end
    local supported = collect(call(self.env.Game, 'GetAllPlayerPawns'))
    if count == 0 then
        local gameState = self:_valid(self.env.CGameState) and self.env.CGameState or self.cgs
        if not gameState and now >= self.nextGameStateLookup then
            self.nextGameStateLookup = now + 1
            self.cgs = module(self.env, 'CGameState', 'GameLua.GameCore.Data.CGameState')
            gameState = self.cgs
        end
        local fallback = call(gameState, 'GetAllCharacters')
        if fallback ~= nil then
            total, unknown = 0, false
            supported = collect(fallback)
        end
    end
    if not supported then self:_error('No supported roster from Game or CGameState') end
    for i = count + 1, #roster do roster[i] = nil end
    self.records, self.rosterOverflow = kept, math.max(0, total - self.maxActors)
    self.rosterOverflowUnknown = unknown
end

function Runtime:_project(pc, world, output)
    output = output or self:_vector2(0, 0)
    output.X, output.Y = 0, 0
    local fn = read(pc, 'ProjectWorldLocationToScreen')
    if type(fn) ~= 'function' then return nil, nil, output end
    local ok, result = pcall(fn, pc, world, output, true)
    if not ok or (result ~= true and result ~= 1) then return nil, nil, output end
    local x, y = point2(output)
    if x then
        local cx, cy = self:_toCanvas(x, y)
        return cx, cy, output
    end
    return nil, nil, output
end

function Runtime:_actor(actor, r, now, pc)
    if not self:_valid(actor) then return false end
    self:_metadata(actor, r, now)
    if r.id == nil or type(r.isBot) ~= 'boolean' then
        self.unknownActors = self.unknownActors + 1
        return false
    end
    if r.id == self.player.id or (self.player.team ~= nil and r.team == self.player.team) then return false end
    local _, x, y, z = self:_location(actor)
    if not x then return false end
    local dx, dy, dz = y / 100 - self.player.x, x / 100 - self.player.y, z / 100 - self.player.z
    if dx * dx + dy * dy + dz * dz > self.range * self.range then return false end
    local health, maxHealth = read(actor, 'Health'), read(actor, 'HealthMax')
    if not finite(maxHealth) or maxHealth <= 0 then maxHealth = read(actor, 'MaxHealth') end
    if not finite(health) or not finite(maxHealth) or maxHealth <= 0 then return false end
    if flag(call(actor, 'IsAlive')) == false then return false end
    local status = read(actor, 'HealthStatus')
    local near = read(self.healthStatus, 'HasLastBreath')
    local finished = read(self.healthStatus, 'FinishedLastBreath')
    local knocked = near ~= nil and status == near
    if finished ~= nil and status == finished then return false end
    if health <= 0 and not knocked then return false end
    r.actor = actor
    r.updatedAt = now
    r.x, r.y, r.z, r.health, r.maxHealth, r.knocked, r.alive = y / 100, x / 100, z / 100, health, maxHealth, knocked, true
    -- Keep the last good screen coordinates instead of invalidating them every tick.
    -- Reprojection is refreshed on movement or at a bounded cadence, which avoids
    -- thousands of ProjectWorldLocationToScreen calls per second in crowded fights.
    local features = self.hud.features
    local headNeeded = features.enabled and (features.names or features.health or features.distance or
        (r.isBot and features.botHeadLines) or (not r.isBot and features.enemyHeadLines))
    local feetNeeded = features.enabled and (features.distance or features.health or
        (r.isBot and features.botFeetLines) or (not r.isBot and features.enemyFeetLines))
    local capsule = r.capsule
    if (headNeeded or feetNeeded) and self:_valid(capsule) then
        local center = call(capsule, 'K2_GetComponentLocation') or call(capsule, 'GetComponentLocation')
        local cx, cy, cz = point(center)
        local half = call(capsule, 'GetScaledCapsuleHalfHeight')
        if cx and finite(half) and half > 0 then
            if headNeeded then
                r.headWorld = r.headWorld or self:_vector3(cx, cy, cz + half)
                r.headWorld.X, r.headWorld.Y, r.headWorld.Z = cx, cy, cz + half
                local cachedH = r._cachedHeadWorld
                local moved = not cachedH or (cachedH.X - cx) ^ 2 + (cachedH.Y - cy) ^ 2 + (cachedH.Z - (cz + half)) ^ 2 > 0.0004
                local projectDue = not r._nextProject or now >= r._nextProject
                if moved or not r.headPix or projectDue then
                    r.headX, r.headY, r.headPix = self:_project(pc, r.headWorld, r.headPix)
                    r._cachedHeadWorld = r._cachedHeadWorld or self:_vector3(0, 0, 0)
                    r._cachedHeadWorld.X, r._cachedHeadWorld.Y, r._cachedHeadWorld.Z = cx, cy, cz + half
                    r._nextProject = now + 0.075
                end
            end
            if feetNeeded then
                r.feetWorld = r.feetWorld or self:_vector3(cx, cy, cz - half)
                r.feetWorld.X, r.feetWorld.Y, r.feetWorld.Z = cx, cy, cz - half
                local cachedF = r._cachedFeetWorld
                local moved = not cachedF or (cachedF.X - cx) ^ 2 + (cachedF.Y - cy) ^ 2 + (cachedF.Z - (cz - half)) ^ 2 > 0.0004
                local projectDue = not r._nextFeetProject or now >= r._nextFeetProject
                if moved or not r.feetPix or projectDue then
                    r.feetX, r.feetY, r.feetPix = self:_project(pc, r.feetWorld, r.feetPix)
                    r._cachedFeetWorld = r._cachedFeetWorld or self:_vector3(0, 0, 0)
                    r._cachedFeetWorld.X, r._cachedFeetWorld.Y, r._cachedFeetWorld.Z = cx, cy, cz - half
                    r._nextFeetProject = now + 0.075
                end
            end
        end
    end
    if (headNeeded and not r.headX) or (feetNeeded and not r.feetX) then
        self.projectionMissing = self.projectionMissing + 1
    end
    return true
end

function Runtime:_yaw(pawn, pc)
    local cm = call(pc, 'GetPlayerCameraManager') or read(pc, 'PlayerCameraManager')
    local rotation = self:_valid(cm) and call(cm, 'GetCameraRotation') or nil
    local yaw = read(rotation, 'Yaw')
    if not finite(yaw) then yaw = read(call(pc, 'GetControlRotation'), 'Yaw') end
    if not finite(yaw) then yaw = read(call(pawn, 'K2_GetActorRotation'), 'Yaw') end
    if finite(yaw) then return yaw * pi / 180 end
end

function Runtime:_drawFrame(pc, now)
    self.hud:resize(self.width, self.height)
    self.adapter:beginFrame()
    self.adapter:syncInput(self.hud, pc, self.toCanvas)
    self.hud:draw(self.width, self.height, now or 0)
    self.adapter:endFrame()
    if not self.adapter:valid() then
        local status = call(self.adapter, 'getStatus')
        self:_error(read(status, 'error') or 'Native renderer became invalid during drawing')
        self:_releaseUI()
        self:_deferSetup(now)
        self.state = 'unsupported_renderer'
        return false
    end
    self.totalFrames = self.totalFrames + 1
    return true
end

function Runtime:_drawMenuOnly(reason, pc, now)
    if not self.menuOnly or self.dataState ~= reason then self:_clearSnapshots() end
    self.menuOnly, self.dataState = true, reason
    if self:_drawFrame(pc, now) then self.state = reason end
end

function Runtime:_step()
    if not self:_licenseAllows() then return end
    local controllerMode = self.mode == 'controller'
    local pc
    if controllerMode then
        local localController
        localController, pc = self:_localController(self.owner)
        if not localController then self:stop() return end
    elseif not self:_local(self.owner) then
        self:stop()
        return
    end
    local now = self:_time()
    self:_retryWeaponCleanup(now)
    if not now and not controllerMode then
        self:stop()
        self.state = 'unsupported_clock'
        self:_error('Engine clock became unavailable')
        return
    end
    if now and self.lastTime and now < self.lastTime then
        self:_releaseUI()
        self.nextSetup, self.nextRoster = now, now
        self.nextGameStateLookup = now
        self.roster, self.records, self.snapshots = {}, {}, {}
    end
    self.lastTime = now
    if self.adapter and (not self:_valid(self.parent) or not self.adapter:valid()) then
        local status = call(self.adapter, 'getStatus')
        self:_error(read(status, 'error') or 'Native overlay or parent canvas became invalid')
        self:_releaseUI()
        self.state = 'waiting_ui'
        self:_deferSetup(now)
    end
    if not self.adapter and not self:_setup(now) then return end
    pc = pc or self:_controller()
    local pawn = self:_pawn(pc)
    if not self:_valid(pc) and not self:_valid(self:_object(pc)) then
        self:_releaseUI()
        self:_deferSetup(now)
        self.state = 'waiting_local_player'
        return
    end
    if not controllerMode then
        if not self:_valid(pawn) then
            self:_releaseUI()
            self:_deferSetup(now)
            self.state = 'waiting_local_player'
            return
        end
        if self:_object(pawn) ~= self:_object(self.owner) then self:stop() return end
    end
    local transformed, reason = self:_transform(pc)
    if not transformed then
        self:_error(reason)
        self:_releaseUI()
        self:_deferSetup(now)
        self.state = 'unsupported_coordinates'
        return
    end
    if not now then
        if self.dataState ~= 'unsupported_clock' then
            self:_error('GameplayStatics.GetTimeSeconds unavailable; menu only, no actor clock substituted')
        end
        self:_drawMenuOnly('unsupported_clock', pc, nil)
        return
    end
    if not self.projectionCoordinates then
        self:_drawMenuOnly('unsupported_projection_coordinates', pc, now)
        return
    end
    if not self:_valid(pawn) then
        self:_drawMenuOnly('waiting_local_player', pc, now)
        return
    end
    if self.activePawn and self:_object(self.activePawn) ~= self:_object(pawn) then self:_clearSnapshots() end
    local _, x, y, z = self:_location(pawn)
    local yaw = self:_yaw(pawn, pc)
    local p = self.player
    if p.sourcePawn ~= pawn or p.sourcePC ~= pc or not p.nextMeta or now >= p.nextMeta then
        local localState = self:_playerState(pawn)
        p.id = self:_key(pawn, localState)
        if not p.id then p.id = self:_key(pc, self:_playerState(pc)) end
        p.team = self:_team(pawn, localState)
        p.sourcePawn, p.sourcePC, p.nextMeta = pawn, pc, now + 0.5
    end
    local key = p.id
    if not x or not yaw or not id(key) then
        if controllerMode then
            self:_drawMenuOnly('waiting_local_data', pc, now)
        else
            self:_releaseUI()
            self:_deferSetup(now)
            self.state = 'waiting_local_data'
        end
        return
    end
    self.activePawn, self.menuOnly, self.dataState = pawn, false, nil
    p.x, p.y, p.z, p.yaw = y / 100, x / 100, z / 100, yaw
    local aiming = read(pawn, 'bIsWeaponAiming')
    p.aiming = aiming == true or aiming == 1
    local count = 0
    self.unknownActors, self.projectionMissing = 0, 0
    local aimEnabled = self:_aimEnabled()
    local aimWorld = aimEnabled and self:_aimWorld() or nil
    if aimEnabled and self.aimContext and self.aimContext.world ~= aimWorld then
        self:_releaseAim()
        self.nextRoster = 0
    end
    if self.hud.features.enabled or (self.hud.visual and self.hud.visual.wallHack) or aimEnabled then
        self:_roster(now)

        -- Crowded-match protection. This throttles only the expensive actor/native
        -- pass; it does not remove or disable any feature.
        local rosterSize = #self.roster
        local passInterval = 1
        if rosterSize > 128 then
            passInterval = 4
        elseif rosterSize > 64 then
            passInterval = 3
        elseif rosterSize > 32 then
            passInterval = 2
        end
        if aimEnabled then
            -- Keep aim data fresher than the visual pass in crowded fights.
            passInterval = math.min(passInterval, 2)
        end
        self.actorPassInterval = passInterval
        self.actorPass = (self.actorPass or 0) + 1

        local doActorPass = passInterval == 1 or
            (self.actorPass % passInterval) == 0 or
            #self.snapshots == 0

        if doActorPass then
            count = 0
            for _, actor in ipairs(self.roster) do
                local record = self.records[actor]
                if record and self:_actor(actor, record, now, pc) then
                    count = count + 1
                    self.snapshots[count] = record
                end
            end
            for i = count + 1, #self.snapshots do self.snapshots[i] = nil end
        else
            -- Reuse the last good snapshot set instead of rebuilding it.
            count = #self.snapshots
        end
    else
        self.nextRoster = 0
        self.actorPass = 0
        for i = 1, #self.snapshots do self.snapshots[i] = nil end
    end
    if type(self.hud.setSourceOverflow) == 'function' then
        self.hud:setSourceOverflow(self.rosterOverflow, not self.rosterOverflowUnknown)
    end
    self.hud:update(self.snapshots, p, now)
    self:_syncVisuals(pawn, now)
    self:_syncWeapons(pawn, now)
    self:_syncBypass(now)
    self:_syncAim(pc, pawn, now, aimWorld)
    if self:_drawFrame(pc, now) then self.state = 'running' end
end

function Runtime:getStatus()
    local renderer = self.adapter and self.adapter:getStatus() or nil
    return {
        state = self.state, ownerActive = self.owner ~= nil, timerActive = self.timer ~= nil,
        controllerMode = self.mode == 'controller', menuOnly = self.menuOnly, dataState = self.dataState,
        projectionCoordinates = self.projectionCoordinates == true, scheduledTicks = self.scheduledTicks,
        frames = self.totalFrames, setupAttempts = self.setupAttempts,
        rosterCount = #self.roster, snapshotCount = #self.snapshots,
        rosterOverflow = self.rosterOverflow, rosterOverflowUnknown = self.rosterOverflowUnknown,
        unknownActors = self.unknownActors,
        projectionMissing = self.projectionMissing, lastError = self.lastError,
        renderer = renderer, visual = self.visuals and self.visuals:getStatus() or self.lastVisualStatus,
        aim = self.aims and call(self.aims, 'getStatus') or self.lastAimStatus,
        weapon = self.weapons and call(self.weapons, 'getStatus') or self.lastWeaponStatus,
        weaponSupported = self.WeaponFeatures ~= nil,
        bypass = self.bypass and call(self.bypass, 'getStatus') or self.lastBypassStatus,
        bypassSupported = self.BypassFeatures ~= nil,
        aimSupported = self.AimFeatures ~= nil, bindingUnverified = true, captureExclusionSupported = false,
        endpointMode = 'scaled_collision_capsule_approximation', updateInterval = 1/30,
        rosterInterval = 0.2, metadataInterval = 0.5, maxActors = self.maxActors
    }
end

return Runtime
end)()

-- ========================================================================
-- 13. CONTROLLER STARTUP AND RETRY
-- ========================================================================

local ShayanESPBootstrap = (function()
local Bootstrap = {}
Bootstrap.__index = Bootstrap
local REGISTRY = '_RedCyanESPBootstrap'
local function read(o, k)
    if o == nil then return nil end
    local ok, v = pcall(function() return o[k] end)
    if ok then return v end
end
local function call(o, k, ...)
    local fn = read(o, k)
    if type(fn) ~= 'function' then return nil end
    local ok, a = pcall(fn, o, ...)
    if ok then return a end
end
function Bootstrap.new(runtime, env, license)
    return setmetatable({
        runtime = runtime, env = env or _G, license = license, generation = 0, logCount = 0,
        started = false, disposed = false, watchdog = nil, controller = nil
    }, Bootstrap)
end
function Bootstrap:_valid(o)
    if o == nil then return false end
    local fn = read(self.env.slua, 'isValid')
    if type(fn) == 'function' then
        local ok, v = pcall(fn, o)
        if ok and v == true then return true end
    end
    return call(self.env.Game, 'IsValid', o) == true
end
function Bootstrap:_controller()
    local getter = read(self.env.GameplayData, 'GetPlayerController')
    if type(getter) == 'function' then
        local ok, pc = pcall(getter)
        if ok and (self:_valid(pc) or self:_valid(read(pc, 'Object'))) then return pc end
    end
    local pc = call(self.env.slua_GameFrontendHUD, 'GetPlayerController')
    if self:_valid(pc) or self:_valid(read(pc, 'Object')) then return pc end
end
function Bootstrap:_report(state)
    self.state = state
    if self.lastLogged == state or self.logCount >= 12 then return end
    self.lastLogged = state
    self.logCount = self.logCount + 1
    if type(self.env.print) == 'function' then pcall(self.env.print, '[RedCyanESP] ' .. state) end
end
function Bootstrap:_clearWatchdog()
    self.generation = self.generation + 1
    if self.watchdog ~= nil then
        call(self.watchdogOwner, self.watchdogClear, self.watchdog)
    end
    self.watchdog, self.watchdogOwner, self.watchdogClear = nil, nil, nil
end
function Bootstrap:_ensureWatchdog()
    local world = self.env.CGameWorld
    if self.watchdogAttempted and self.watchdogWorld == world and self.watchdogPC == self.controller then return end
    self:_clearWatchdog()
    self.watchdogAttempted = true
    self.watchdogWorld = world
    self.watchdogPC = self.controller
    local host, add, remove = self.env.Game, 'SetTimer', 'ClearTimer'
    if type(read(host, add)) ~= 'function' or type(read(host, remove)) ~= 'function' then
        host, add, remove = self.controller, 'AddGameTimer', 'RemoveGameTimer'
    end
    if type(read(host, add)) ~= 'function' or type(read(host, remove)) ~= 'function' then
        self.watchdogAttempted = false
        self.lastError = 'No paired watchdog timer API; character callbacks can retry startup'
        return
    end
    local generation = self.generation
    local fn = function()
        if self.disposed or generation ~= self.generation then return end
        local ok, err = pcall(self.refresh, self)
        if not ok then
            self.lastError = tostring(err):sub(1, 220)
            self:_report('startup_error')
        end
    end
    local ok, handle = pcall(read(host, add), host, 1, true, fn)
    if not ok or handle == nil then
        self.generation = self.generation + 1
        self.lastError = ok and 'Watchdog timer supplied no removable handle' or tostring(handle):sub(1, 220)
        return
    end
    self.watchdog, self.watchdogOwner, self.watchdogClear = handle, host, remove
    self.lastError = nil
end
function Bootstrap:refresh()
    if self.disposed then return false end
    call(self.runtime, 'maintenance')
    local pc = self:_controller()
    local world = self.env.CGameWorld
    if pc ~= self.controller or world ~= self.controllerWorld then
        if self.controller then pcall(self.runtime.forgetController, self.runtime, self.controller) end
        self.controller, self.controllerWorld = pc, world
    end
    if self.license and type(self.license.update) == 'function' then
        local ok = pcall(self.license.update, self.license)
        if not ok then self.licenseError = 'license_update_failed' end
        local active = false
        if type(self.license.isActive) == 'function' then
            local okActive, value = pcall(self.license.isActive, self.license)
            active = okActive and value == true
        end
        if not active then
            self.licenseBlocked = true
            self:_report('license_required')
            self:_ensureWatchdog()
            return false
        end
        self.licenseBlocked = false
    end
    local attached = false
    if pc then
        local ok, result = pcall(self.runtime.considerController, self.runtime, pc)
        attached = ok and result == true
        if not ok then self.lastError = tostring(result):sub(1, 220) end
        local status = call(self.runtime, 'getStatus')
        self:_report(attached and ('controller_' .. tostring(read(status, 'state') or 'ready')) or 'waiting_controller_timer')
    else
        self:_report('waiting_controller')
    end
    self:_ensureWatchdog()
    return attached
end
function Bootstrap:start()
    if self.disposed then return false end
    if not self.started then
        local registry = self.env._G or self.env
        local old = read(registry, REGISTRY)
        if old and old ~= self and type(read(old, 'dispose')) == 'function' then pcall(old.dispose, old) end
        registry[REGISTRY] = self
        self.registry = registry
        self.started = true
        self:_report('module_loaded')
    end
    return self:refresh()
end
function Bootstrap:getStatus()
    return {
        started = self.started, disposed = self.disposed, state = self.state,
        controllerAvailable = self.controller ~= nil, watchdogActive = self.watchdog ~= nil,
        lastError = self.lastError, licenseError = self.licenseError, licenseBlocked = self.licenseBlocked == true
    }
end
function Bootstrap:dispose()
    if self.disposed then return end
    self.disposed = true
    self:_clearWatchdog()
    pcall(self.runtime.stop, self.runtime)
    -- Keep the license in a process-level session; do not dispose it here.
    -- The session license is managed separately from the HUD lifecycle.
    if self.registry and self.registry[REGISTRY] == self then self.registry[REGISTRY] = nil end
    self.controller = nil
end
return Bootstrap
end)()

-- ========================================================================
-- 13.5 AUTO-RUN LIBANOGS BYPASS
-- ========================================================================

local ShayanAnogsBypass = (function()
    local SH = _G.ScriptHelperClient
    if not SH then
        return { ready = false, reason = 'ScriptHelperClient unavailable' }
    end
    local KNOWN_PKGS = {
        ["com.tencent.ig"]    = "/data/app/~~2U5OPyLPSNrCp3Jhv6O4Xg==/com.tencent.ig-rxZaOzwfUVAPdioMsk4emQ==/lib/arm64/",
        ["com.pubg.krmobile"] = "/data/app/~~uBLiktAOPJCRfbQA01C-3Q==/com.pubg.krmobile-nhvnm6_ClIAV0J93P86daw==/lib/arm64/",
        ["com.pubg.imobile"]  = "/data/app/~~p9qsLKUJYSx0V20AUx9EWg==/com.pubg.imobile-oEDhX_GaHiB7HYo8hWh0Hg==/lib/arm64/",
    }
    local function detectPackage()
        if SH.GetNativePackageTag then
            local ok, p = pcall(SH.GetNativePackageTag)
            if ok and type(p) == "string" and KNOWN_PKGS[p] then return p end
        end
        for p in pairs(KNOWN_PKGS) do return p end
        return "com.tencent.ig"
    end
    local PKG     = detectPackage()
    local LIBDIR  = KNOWN_PKGS[PKG] or ""
    local LIBFILE = LIBDIR .. "libanogs.so"
    local APPLIED_PATCH = {}
    local APPLIED_HOOK  = {}
    local BASE_CACHE    = {}
    local function kdup(lib, off) return string.format("%s@0x%X", lib, off) end
    local function getBase(lib)
        if BASE_CACHE[lib] then return BASE_CACHE[lib] end
        local b = 0
        local ok, r = pcall(SH.GetPUBGModuleBaseAddr, lib)
        if ok and type(r) == "number" then b = r
        elseif ok and type(r) == "table" then b = r.base or r.addr or r[1] or 0 end
        if b == 0 then
            local alt = lib:gsub("%.so$", "")
            local ok2, r2 = pcall(SH.GetPUBGModuleBaseAddr, alt)
            if ok2 and type(r2) == "number" then b = r2 end
        end
        BASE_CACHE[lib] = b
        return b
    end
    local function hex2bin(h)
        return (h:gsub("%x%x", function(b) return string.char(tonumber(b, 16)) end))
    end
    local function applyPatch(lib, off, hexbytes)
        local base = getBase(lib)
        local addr = base > 0 and (base + off) or nil
        if SH.ProcessSoPatch and addr then
            local ok = pcall(SH.ProcessSoPatch, addr, hexbytes)
            if ok then return true, "P1" end
        end
        if SH.ProcessSoPatch and addr then
            local ok = pcall(SH.ProcessSoPatch, addr, hex2bin(hexbytes))
            if ok then return true, "P2" end
        end
        if SH.ProcessSoPatch then
            local ok = pcall(SH.ProcessSoPatch, {
                { module = lib, offset = off, addr = addr,
                  bytes = hexbytes, data = hex2bin(hexbytes) }
            })
            if ok then return true, "P3" end
        end
        if SH.WriteFileAtPath and SH.SetUpdatedSoPatchFile and SH.ProcessSoPatch then
            local data = string.format("%s|0x%X|%s", lib, off, hexbytes)
            local paths = {
                "/storage/emulated/0/Android/data/" .. PKG .. "/files/anogs.bin",
                "/sdcard/Android/data/" .. PKG .. "/files/anogs.bin",
                "/data/local/tmp/anogs.bin",
            }
            for _, path in ipairs(paths) do
                local okW = pcall(SH.WriteFileAtPath, path, data)
                if okW then
                    pcall(SH.SetUpdatedSoPatchFile, path)
                    local okP = pcall(SH.ProcessSoPatch)
                    if okP then return true, "P4" end
                end
            end
        end
        return false, "no-path"
    end
    local function installHook(lib, off, handler)
        local base = getBase(lib)
        if _G.__FRAMEWORK_HOOK_LIB_NO_ORIG then
            local ok = pcall(_G.__FRAMEWORK_HOOK_LIB_NO_ORIG, lib, off, handler)
            if ok then return true, "H1" end
        end
        if SH.InstallHook then
            local ok = pcall(SH.InstallHook, lib, off, handler)
            if ok then return true, "H2a" end
        end
        if SH.HookFunction then
            local ok = pcall(SH.HookFunction, lib, off, handler)
            if ok then return true, "H2b" end
        end
        if SH.AddHook then
            local ok = pcall(SH.AddHook, lib, off, handler)
            if ok then return true, "H2c" end
        end
        if SH.AllocVirMem and SH.ProcessSoPatch and base > 0 then
            local slot = pcall(SH.AllocVirMem, 16)
            if slot and type(slot) == "number" and slot > 0 then
                return false, "H3-no-native-bridge"
            end
        end
        return false, "no-hook-api"
    end
    local function PATCH_LIB(lib, offStr, bytes)
        local off = tonumber(offStr)
        if not off then return end
        local k = kdup(lib, off)
        if APPLIED_PATCH[k] then return end
        local ok, how = applyPatch(lib, off, bytes)
        if ok then
            APPLIED_PATCH[k] = true
            print(string.format("[ANOGS] patch %s @0x%X [%s] via %s", lib, off, bytes, how))
        else
            print(string.format("[ANOGS] patch %s @0x%X FAILED (%s)", lib, off, how))
        end
    end
    local function HOOK_LIB_NO_ORIG(lib, offStr, handler)
        local off = tonumber(offStr)
        if not off then return end
        local k = kdup(lib, off)
        if APPLIED_HOOK[k] then return end
        local ok, how = installHook(lib, off, handler)
        if ok then
            APPLIED_HOOK[k] = true
            print(string.format("[ANOGS] hook %s @0x%X via %s", lib, off, how))
        else
            print(string.format("[ANOGS] hook %s @0x%X FAILED (%s)", lib, off, how))
        end
    end
    local function Shayan(...) return 0 end
    _G.Shayan = Shayan
    local function applyAll()
        PATCH_LIB("libanogs.so", "0x2328F0", "C0 03 5F D6")
        PATCH_LIB("libanogs.so", "0x213360", "C0 03 5F D6")
        PATCH_LIB("libanogs.so", "0x2ECE70", "C0 03 5F D6")
        PATCH_LIB("libanogs.so", "0x4D5998", "00 00 80 D2 C0 03 5F D6")
        PATCH_LIB("libanogs.so", "0x4D59A4", "00 00 80 D2 C0 03 5F D6")
        PATCH_LIB("libanogs.so", "0x4D4DB4", "00 00 80 D2 C0 03 5F D6")
        PATCH_LIB("libanogs.so", "0x4D4DD0", "00 00 80 D2 C0 03 5F D6")
        PATCH_LIB("libanogs.so", "0x4D571C", "00 00 80 D2 C0 03 5F D6")
        PATCH_LIB("libanogs.so", "0x4D5748", "00 00 80 D2 C0 03 5F D6")
        HOOK_LIB_NO_ORIG("libanogs.so", "0x371418", Shayan)
        HOOK_LIB_NO_ORIG("libanogs.so", "0x431800", Shayan)
        HOOK_LIB_NO_ORIG("libanogs.so", "0x39F56C", Shayan)
        HOOK_LIB_NO_ORIG("libanogs.so", "0x3A564C", Shayan)
    end
    applyAll()
    return {
        ready            = true,
        pkg              = PKG,
        libfile          = LIBFILE,
        applied_patch    = APPLIED_PATCH,
        applied_hook     = APPLIED_HOOK,
        PATCH_LIB        = PATCH_LIB,
        HOOK_LIB_NO_ORIG = HOOK_LIB_NO_ORIG,
    }
end)()
_G.__ShayanAnogsBypass = ShayanAnogsBypass

-- ========================================================================
-- 13.6 LAG FIX PATCH
-- ========================================================================

local ShayanLagFix = (function()
    local Patch = {}
    local ORIGINAL_SYNC_VISUALS = ShayanESPRuntime._syncVisuals
    ShayanESPRuntime._syncVisuals = function(self, pawn, now)
        if not self.visuals then
            local settings = self.hud and self.hud.visual
            if not settings or (not settings.ipadView and not settings.wallHack) then return end
        end
        return ORIGINAL_SYNC_VISUALS(self, pawn, now)
    end

    local ORIGINAL_SYNC_WEAPONS = ShayanESPRuntime._syncWeapons
    ShayanESPRuntime._syncWeapons = function(self, pawn, now)
        if not self.weapons and not self.weaponRetiring then
            local settings = self.hud and self.hud.aim
            if not settings or settings.smallCrosshair ~= true then return end
        end
        return ORIGINAL_SYNC_WEAPONS(self, pawn, now)
    end

    local ORIGINAL_SYNC_BYPASS = ShayanESPRuntime._syncBypass
    ShayanESPRuntime._syncBypass = function(self, now)
        if not self.bypass and not self.bypassRetiring then
            if not self.BypassFeatures then return end
        end
        return ORIGINAL_SYNC_BYPASS(self, now)
    end

    local ORIGINAL_SYNC_AIM = ShayanESPRuntime._syncAim
    ShayanESPRuntime._syncAim = function(self, pc, pawn, now, snapshotWorld)
        if not self.aims and not self:_aimEnabled() then return end
        return ORIGINAL_SYNC_AIM(self, pc, pawn, now, snapshotWorld)
    end

    local ORIGINAL_SETUP = ShayanESPRuntime._setup
    ShayanESPRuntime._setup = function(self, now)
        local ok = ORIGINAL_SETUP(self, now)
        if ok and self.adapter and not self._lagWarmed then
            self._lagWarmed = true
            local warm = self.adapter._beginActor
            if type(warm) == 'function' then
                for i = 1, 24 do
                    pcall(warm, self.adapter, '__warm_' .. i, 0, 0, 1, 1)
                    if type(self.adapter.endActor) == 'function' then
                        pcall(self.adapter.endActor, self.adapter)
                    end
                end
                if type(self.adapter.endFrame) == 'function' then
                    pcall(self.adapter.endFrame, self.adapter)
                end
            end
        end
        return ok
    end

    local ORIGINAL_VIS_UPDATE = ShayanVisualFeatures.new
    ShayanVisualFeatures.new = (function(orig)
        return function(env)
            local v = orig(env)
            if v and type(v) == 'table' then
                local origUpdate = v.update
                v.update = function(self, pawn, snapshots, settings, now)
                    local wantWall = settings and settings.wallHack == true
                    local wantFov = settings and settings.ipadView == true
                    if not wantWall and not wantFov
                        and (not self.ownedOrder or #self.ownedOrder == 0) then
                        return
                    end
                    return origUpdate(self, pawn, snapshots, settings, now)
                end
            end
            return v
        end
    end)(ShayanVisualFeatures.new)

    local ORIGINAL_DRAW = ShayanHUD.draw
    ShayanHUD.draw = function(self, width, height, now)
        local f = self.features
        local noActors = self.count == 0
        local nothing = noActors
            and not f.compass and not f.enemyCount and not f.botCount
            and not self.open
        if nothing and self._lagLastNoop and (now - self._lagLastNoop) < 0.5 then
            return true
        end
        if nothing then self._lagLastNoop = now end
        return ORIGINAL_DRAW(self, width, height, now)
    end

    local ORIGINAL_HUD_NEW = ShayanHUD.new
    ShayanHUD.new = function(renderer, config)
        config = type(config) == 'table' and config or {}
        if not config.labelInterval then config.labelInterval = 0.2 end
        if not config.staleAfter then config.staleAfter = 0.6 end
        return ORIGINAL_HUD_NEW(renderer, config)
    end

    Patch.applied = true
    Patch.version = '1.0'
    Patch.hotfixes = {
        '50Hz->30Hz tick (baked)',
        'transform cache (baked)',
        'metadata cache (baked)',
        'projection cache (baked)',
        'health arc 24->8 (baked)',
        'HUD name+distance merge (baked)',
        'resize skip (baked)',
        'touch poll gating (baked)',
        'sync short-circuits',
        'actor pool warm',
        'visual cadence (baked 0.25s)',
        'bypass slim wrapper (baked)',
        'HUD noop skip',
        'label interval 5Hz',
    }
    return Patch
end)()

_G.__ShayanLagFix = ShayanLagFix

-- ==================== CROWD PERFORMANCE HOTFIX ====================
-- The original late hotfixes were fighting the caches above: one explicitly
-- invalidated projection caches every frame and another forced metadata refreshes.
-- Keep every feature, but let the existing caches actually work.
local ORIGINAL_METADATA_SAFE = ShayanESPRuntime._metadata
ShayanESPRuntime._metadata = function(self, actor, record, now)
    -- Metadata changes slowly compared with movement. Refresh every 1.5s, or
    -- immediately if the cached identity is incomplete.
    if record.id ~= nil and type(record.isBot) == 'boolean' and record.team ~= nil
        and record.name ~= nil and record._metaNext and now < record._metaNext then
        return
    end
    record._metaNext = now + 1.5
    return ORIGINAL_METADATA_SAFE(self, actor, record, now)
end

local ORIGINAL_DRAW_SAFE = ShayanHUD.draw
ShayanHUD.draw = function(self, width, height, now)
    -- Preserve all active features. Only skip an entirely empty frame when
    -- nothing is visible and the menu is closed.
    local f = self.features
    if self.count == 0 and not self.open and not f.compass and not f.enemyCount and not f.botCount then
        return true
    end
    return ORIGINAL_DRAW_SAFE(self, width, height, now)
end

-- ==================== WATERMARK MODULE ====================
local ShayanWatermark = (function()
    local WM = {
        widget = nil, slot = nil, adapter = nil,
        enabled = true, text = "SHAYAN",
        size = 22, x = 0, y = 0, pulseSpeed = 0.8,
    }
    WM.__index = WM
    local function finite(v) return type(v) == 'number' and v == v and v > -math.huge and v < math.huge end

    function WM.new(env)
        return setmetatable({ env = env or _G }, WM)
    end

    function WM:_valid(o)
        if o == nil then return false end
        local slua = self.env.slua
        if slua and type(slua.isValid) == 'function' then
            local ok, v = pcall(slua.isValid, o)
            if ok and v == true then return true end
        end
        local g = self.env.Game
        if g and type(g.IsValid) == 'function' then
            local ok, v = pcall(g.IsValid, o)
            return ok and v == true
        end
        return true
    end

    function WM:_color(r, g, b, a)
        local ctor = self.env.FLinearColor
        if ctor == nil then
            local imp = self.env.import
            if type(imp) == 'function' then
                local ok, c = pcall(imp, 'LinearColor')
                if ok then ctor = c end
            end
        end
        if ctor then
            local ok, c = pcall(ctor, r, g, b, a or 1)
            if ok and c then return c end
        end
        return { R = r, G = g, B = b, A = a or 1 }
    end

    function WM:_slate(color)
        local ctor = self.env.FSlateColor
        if ctor == nil then
            local imp = self.env.import
            if type(imp) == 'function' then
                local ok, c = pcall(imp, 'SlateColor')
                if ok then ctor = c end
                if ctor == nil then
                    ok, c = pcall(imp, '/Script/SlateCore.SlateColor')
                    if ok then ctor = c end
                end
            end
        end
        if ctor then
            local ok, c = pcall(ctor, color)
            if ok and c then return c end
        end
        return color
    end

    function WM:_vec(x, y)
        local ctor = self.env.FVector2D
        if ctor == nil then
            local imp = self.env.import
            if type(imp) == 'function' then
                local ok, c = pcall(imp, 'Vector2D')
                if ok then ctor = c end
            end
        end
        if ctor then
            local ok, v = pcall(ctor, x, y)
            if ok and v then return v end
        end
        return { X = x, Y = y }
    end

    function WM:_ensure(adapter)
        if not adapter or not adapter.root then return false end
        local root = adapter.root.widget
        if not self:_valid(root) then return false end

        -- Match/module refresh can replace the HUD root while the old
        -- TextBlock is still technically a valid UObject. Rebind the
        -- original watermark to the current root instead of reusing the
        -- detached widget from the previous match.
        if self.widget and self:_valid(self.widget) then
            local sameAdapter = (self.adapter == adapter)
            local sameRoot = (self.rootWidget == root)
            if sameAdapter and sameRoot then
                local parentOk = true
                local hasParent = type(self.widget.GetParent) == 'function'
                if hasParent then
                    local okParent, parent = pcall(self.widget.GetParent, self.widget)
                    parentOk = okParent and self:_valid(parent) and parent == root
                end
                if parentOk then return true end
            end
            self:destroy()
        elseif self.widget or self.slot then
            self:destroy()
        end
        local cg = self.env.CGame
        if not cg or type(cg.NewObjectFromPath) ~= 'function' then return false end
        local ok, widget = pcall(cg.NewObjectFromPath, cg, '/Script/UMG.TextBlock', root)
        if not ok or not self:_valid(widget) then return false end
        local slotOk, slot = pcall(root.AddChildToCanvas, root, widget)
        if not slotOk or not slot then
            pcall(widget.RemoveFromParent, widget)
            pcall(widget.ConditionalBeginDestroy, widget)
            return false
        end
        pcall(slot.SetAutoSize, slot, true)
        pcall(slot.SetZOrder, slot, 99999)
        pcall(slot.SetAlignment, slot, self:_vec(1.0, 1.0))
        pcall(widget.SetText, widget, self.text)
        pcall(function()
            local font = widget.Font
            if font then
                font.Size = self.size
                widget.Font = font
            end
        end)
        local ue = self.env.UEnums
        if ue and ue.ESlateVisibility then
            pcall(widget.SetWidgetVisibility, widget, ue.ESlateVisibility.SelfHitTestInvisible)
        end
        self.widget, self.slot, self.adapter = widget, slot, adapter
        self.rootWidget = root
        return true
    end

    function WM:update(adapter, width, height, now)
        if not self.enabled then
            if self.widget then self:destroy() end
            return
        end
        if not self:_ensure(adapter) then return end
        local t = finite(now) and now or 0
        local r = math.sin(t * self.pulseSpeed) * 0.5 + 0.5
        local g = math.sin(t * self.pulseSpeed + 2.094) * 0.5 + 0.5
        local b = math.sin(t * self.pulseSpeed + 4.188) * 0.5 + 0.5
        local lc = self:_color(r, g, b, 1)
        pcall(self.widget.SetColorAndOpacity, self.widget, self:_slate(lc))
        if self.slot and finite(width) and finite(height) then
            local marginX = 24
            local marginY = 24
            local cx = width - marginX + self.x
            local cy = height - marginY + self.y
            pcall(self.slot.SetPosition, self.slot, self:_vec(cx, cy))
        end
    end

    function WM:destroy()
        if self.widget then
            pcall(self.widget.RemoveFromParent, self.widget)
            pcall(self.widget.ConditionalBeginDestroy, self.widget)
        end
        self.widget, self.slot, self.adapter, self.rootWidget = nil, nil, nil, nil
    end

    return WM
end)()
_G.__ShayanWatermark = ShayanWatermark

-- ==================== WATERMARK HOOK ====================
local ORIGINAL_STEP_WM = ShayanESPRuntime._step
ShayanESPRuntime._step = function(self)
    ORIGINAL_STEP_WM(self)
    if not _G.__ShayanWatermark then return end
    if not self._watermark then
        self._watermark = _G.__ShayanWatermark.new(self.env)
    end
    pcall(self._watermark.update, self._watermark, self.adapter, self.width, self.height, self.lastTime)
end

-- ========================================================================
-- 14. CONNECTION TO ORIGINAL CALLBACKS
-- ========================================================================

local ShayanESPRuntimeInstance, ShayanESPBootstrapInstance, ShayanESPLifecycleError
local ShayanESPLicenseInstance
local function ShayanESPEnsureRuntime()
    -- Persist license, runtime, and bootstrap instances in process memory.
    -- This preserves the sign-in session across match-level module reloads.
    -- A new game process still requires a fresh sign-in.
    if _G.__ShayanESPRuntimeInstance and _G.__ShayanESPLicenseInstance then
        ShayanESPRuntimeInstance   = _G.__ShayanESPRuntimeInstance
        ShayanESPLicenseInstance   = _G.__ShayanESPLicenseInstance
        ShayanESPBootstrapInstance = _G.__ShayanESPBootstrapInstance
        return
    end
    if not ShayanESPRuntimeInstance then
        local host = setmetatable({ GameplayData = GameplayData }, { __index = _ENV })
        ShayanESPLicenseInstance = ShayanLicenseRuntime.new(
            host, ShayanLicenseConfig, ShayanLicenseCore, ShayanLoginUI)
        ShayanESPRuntimeInstance = ShayanESPRuntime.new(
            ShayanHUD, ShayanUMGAdapter, host,
            ShayanVisualFeatures, ShayanAimFeatures, ShayanWeaponFeatures,
            ShayanESPLicenseInstance, ShayanBypassFeatures)
        if ShayanESPBootstrap then
            ShayanESPBootstrapInstance = ShayanESPBootstrap.new(
                ShayanESPRuntimeInstance, host, ShayanESPLicenseInstance)
        end
        -- Persist karo
        _G.__ShayanESPRuntimeInstance   = ShayanESPRuntimeInstance
        _G.__ShayanESPLicenseInstance   = ShayanESPLicenseInstance
        _G.__ShayanESPBootstrapInstance = ShayanESPBootstrapInstance
    end
end
local function ShayanESPInvoke(method, owner)
    local ok, err = pcall(function()
        if not ShayanESPRuntimeInstance then
            if method ~= 'consider' then return end
            ShayanESPEnsureRuntime()
        end
        if method == 'consider' and ShayanESPBootstrapInstance then
            if ShayanESPBootstrapInstance:start() then return end
        end
        ShayanESPRuntimeInstance[method](ShayanESPRuntimeInstance, owner)
    end)
    if not ok then ShayanESPLifecycleError = tostring(err):sub(1, 240) end
end

if ShayanESPBootstrap then
    local ok, err = pcall(function()
        ShayanESPEnsureRuntime()
        if ShayanESPLicenseInstance and type(ShayanESPLicenseInstance.update) == 'function' then
            pcall(ShayanESPLicenseInstance.update, ShayanESPLicenseInstance)
        end
        ShayanESPBootstrapInstance:start()
    end)
    if not ok then ShayanESPLifecycleError = tostring(err):sub(1, 240) end
end

local function ShayanESPAfterOriginal(name)
    local original = assert(CharacterBase[name], 'Missing original callback: ' .. name)
    CharacterBase[name] = function(self, ...)
        local result = table.pack(original(self, ...))
        ShayanESPInvoke('consider', self)
        return table.unpack(result, 1, result.n)
    end
end

local function ShayanESPBeforeCleanup(name)
    local original = assert(CharacterBase[name], 'Missing original callback: ' .. name)
    CharacterBase[name] = function(self, ...)
        ShayanESPInvoke('forget', self)
        return original(self, ...)
    end
end

ShayanESPAfterOriginal('ReceiveBeginPlay')
ShayanESPAfterOriginal('ReceivePossessed')
ShayanESPBeforeCleanup('ReceiveEndPlay')
ShayanESPBeforeCleanup('OnDestroyed')

function CharacterBase:GetESPStatus()
    local status = { state = 'idle', captureExclusionSupported = false, bindingUnverified = true }
    if ShayanESPRuntimeInstance then
        local ok, result = pcall(ShayanESPRuntimeInstance.getStatus, ShayanESPRuntimeInstance)
        if ok and type(result) == 'table' then status = result
        elseif not ok then ShayanESPLifecycleError = tostring(result):sub(1, 240) end
    end
    status.lifecycleError = ShayanESPLifecycleError
    if ShayanESPLicenseInstance then
        local ok, value = pcall(ShayanESPLicenseInstance.getStatus, ShayanESPLicenseInstance)
        status.license = ok and value or { active = false, state = 'license_unavailable' }
    end
    if ShayanESPBootstrapInstance then
        local ok, value = pcall(ShayanESPBootstrapInstance.getStatus, ShayanESPBootstrapInstance)
        if ok then status.bootstrap = value end
    end
    if _G.__ShayanLagFix then
        status.lagFix = { applied = true, version = _G.__ShayanLagFix.version, hotfixes = _G.__ShayanLagFix.hotfixes }
    end
    return status
end

function CharacterBase:SubmitESPKey(key)
    if not ShayanESPLicenseInstance then return false, 'license_unavailable' end
    local ok, result, reason = pcall(ShayanESPLicenseInstance.login, ShayanESPLicenseInstance, key)
    if not ok then return false, 'license_unavailable' end
    return result, reason
end

function CharacterBase:LogoutESP()
    if not ShayanESPLicenseInstance then return false end
    local ok = pcall(ShayanESPLicenseInstance.logout, ShayanESPLicenseInstance)
    if ShayanESPRuntimeInstance then pcall(ShayanESPRuntimeInstance.stop, ShayanESPRuntimeInstance) end
    return ok
end

-- ============================================================
-- AUTO FEEDBACK SYSTEM (Telegram) - ALL RANKS SUPPORTED
-- ============================================================
local AutoFeedback = {
	Config = {
		ServerURL = "https://shaya-lua-fbn.shadowcheatss-1.workers.dev/",
		TestMode = false
	},
	Hooked = false
}

local function AF_Log(message)
	print(string.format("[SHAYAN][%s] %s", os.date("%H:%M:%S"), tostring(message)))
end

local function AF_Notify(message)
	if _G.SRCHUBNotify then
		pcall(_G.SRCHUBNotify, message)
	end
end

local function AF_GetModule(name, allowRequire)
	local loaded = package and package.loaded and package.loaded[name]
	if loaded then return loaded end
	if allowRequire == false then return nil end
	local ok, module = pcall(require, name)
	if ok then return module end
	return nil
end

local function AF_AddTimerOnce(delay, callback)
	local ticker = AF_GetModule("common.time_ticker")
	if ticker and type(ticker.AddTimerOnce) == "function" then
		ticker.AddTimerOnce(delay, callback)
		return true
	end
	return false
end

local function AF_Base64Encode(data)
	if type(data) ~= "string" or #data == 0 then return "" end
	local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	local output = {}
	local outputIndex = 0
	local index = 1
	while index <= #data - 2 do
		local a, b, c = string.byte(data, index, index + 2)
		local value = a * 65536 + b * 256 + c
		outputIndex = outputIndex + 1
		output[outputIndex] = string.char(
			string.byte(alphabet, math.floor(value / 262144) + 1),
			string.byte(alphabet, math.floor(value / 4096) % 64 + 1),
			string.byte(alphabet, math.floor(value / 64) % 64 + 1),
			string.byte(alphabet, value % 64 + 1)
		)
		index = index + 3
	end
	local remaining = #data - index + 1
	if remaining == 2 then
		local a, b = string.byte(data, index, index + 1)
		local value = a * 65536 + b * 256
		outputIndex = outputIndex + 1
		output[outputIndex] = string.char(
			string.byte(alphabet, math.floor(value / 262144) + 1),
			string.byte(alphabet, math.floor(value / 4096) % 64 + 1),
			string.byte(alphabet, math.floor(value / 64) % 64 + 1),
			string.byte("=")
		)
	elseif remaining == 1 then
		local value = string.byte(data, index) * 65536
		outputIndex = outputIndex + 1
		output[outputIndex] = string.char(
			string.byte(alphabet, math.floor(value / 262144) + 1),
			string.byte(alphabet, math.floor(value / 4096) % 64 + 1),
			string.byte("="),
			string.byte("=")
		)
	end
	return table.concat(output)
end

local function AF_UrlEncode(value)
	if value == nil then return nil end
	value = tostring(value):gsub("\n", "\r\n")
	value = value:gsub("([^A-Za-z0-9 %-%_%.%~])", function(character)
		return string.format("%%%02X", string.byte(character))
	end)
	value = value:gsub(" ", "+")
	return value
end

local function AF_ReadFile(path)
	local file = io.open(path, "rb")
	if not file then return "" end
	local data = file:read("*a") or ""
	file:close()
	return data
end

local function AF_RemoveFile(path)
	pcall(os.remove, path)
end

local function AF_GetRankName(rank)
	if rank < 1700 then return "Bronze"
	elseif rank < 2200 then return "Silver"
	elseif rank < 2700 then return "Gold"
	elseif rank < 3200 then return "Platinum"
	elseif rank < 3700 then return "Diamond"
	elseif rank < 4200 then return "Crown"
	elseif rank < 4700 then return "Ace"
	elseif rank < 5200 then return "Ace Master"
	elseif rank < 5600 then return "Ace Dominator"
	end
	return "Conqueror"
end

-- Telegram HTML caption: <blockquote> creates the quote highlight, <code> preserves
-- the complete player name/UID. Escape all live fields before injecting into HTML.
local function AF_EscapeTelegramHTML(value)
    return tostring(value == nil and "" or value)
        :gsub("&", "&amp;")
        :gsub("<", "&lt;")
        :gsub(">", "&gt;")
end

local AF_NameFields = {
    "name", "Name", "nickname", "nickName", "NickName", "Nick", "roleName",
    "RoleName", "role_name", "playerName", "PlayerName", "userName", "UserName"
}
local AF_UidFields = {"uid", "UID", "roleId", "roleID", "RoleId", "playerUid", "playerUID"}

local function AF_ReadTextField(object, fieldNames)
    if type(object) ~= "table" and type(object) ~= "userdata" then return nil end
    for _, field in ipairs(fieldNames) do
        local ok, value = pcall(function() return object[field] end)
        if ok and (type(value) == "string" or type(value) == "number") then
            local result = tostring(value):gsub("[%c]", " "):match("^%s*(.-)%s*$")
            if result and result ~= "" and result ~= "unknown" then
                return result
            end
        end
    end
    return nil
end

local function AF_GetPlayerIdentity()
    local dataMgr = _G.DataMgr
    local roleData = dataMgr and dataMgr.roleData
    local profiles = {}
    local function AddProfile(value)
        if value ~= nil then profiles[#profiles + 1] = value end
    end
    AddProfile(roleData)
    if roleData then
        -- Different clients place nickname/UID in different profile sub-tables.
        for _, key in ipairs({"roleInfo", "roleBaseInfo", "baseInfo", "userInfo"}) do
            local ok, nested = pcall(function() return roleData[key] end)
            if ok then AddProfile(nested) end
        end
    end
    if dataMgr then
        for _, key in ipairs({"playerData", "userData", "roleInfo", "userInfo"}) do
            local ok, nested = pcall(function() return dataMgr[key] end)
            if ok then AddProfile(nested) end
        end
    end
    -- Only live local-player data is used; never substitute a fabricated name.
    local name, uid
    for _, profile in ipairs(profiles) do
        name = name or AF_ReadTextField(profile, AF_NameFields)
        uid = uid or AF_ReadTextField(profile, AF_UidFields)
        if name and uid then break end
    end
    if not uid and _G._KONG_UK ~= nil then
        uid = tostring(_G._KONG_UK)
    end
    return name or "Not available", uid or "Not available"
end

local FeedbackCaptionTemplate = table.concat({
    "🏆 <b>SHAYAN • VICTORY REPORT</b>",
    "━━━━━━━━━━━━━━━━━━",
    "<blockquote>🎮 <b>PLAYER DETAILS</b>",
    "👤 <b>Nickname</b>  <code>%s</code>",
    "🆔 <b>Player UID</b>  <code>%s</code>",
    "💀 <b>Total Kills</b>  <code>%d</code>",
    "🎖 <b>Current Rank</b>  <code>%s</code>",
    "🕒 <b>Match Time</b>  <code>%s</code></blockquote>",
    "✅ <b>STATUS: MATCH COMPLETED</b>",
    "⚡ <b>SHAYAN AUTO FEEDBACK</b>",
    "👑 <b>Owner:</b> @SHAYAN_OWNER"
}, "\n")

function AutoFeedback.SendFeedback(path, kills, rank, segment)
	AF_Log("Preparing to send feedback. Screenshot: " .. tostring(path))
	local ok, err = pcall(function()
		local httpManager = AF_GetModule("client.slua.logic.http.http_manager")
		if not httpManager or type(httpManager.Post) ~= "function" then
			AF_Log("HTTP manager is unavailable.")
			return
		end
		local attempts = 0
		local function TrySend()
			local imageData = AF_ReadFile(path)
			if #imageData > 0 then
                local playerName, uid = AF_GetPlayerIdentity()
                kills = tonumber(kills) or 0
                rank = tonumber(rank) or 0
                segment = tonumber(segment) or 0
                local rankLabel = rank > 0 and AF_GetRankName(rank) or "Not available"
                local caption = string.format(
                    FeedbackCaptionTemplate,
                    AF_EscapeTelegramHTML(playerName),
                    AF_EscapeTelegramHTML(uid),
                    kills,
                    AF_EscapeTelegramHTML(rankLabel),
                    AF_EscapeTelegramHTML(os.date("%d/%m/%Y • %I:%M %p"))
                )
				local encodedImage = AF_Base64Encode(imageData)
				encodedImage = encodedImage:gsub("%+", "%%2B")
				encodedImage = encodedImage:gsub("/", "%%2F")
				encodedImage = encodedImage:gsub("=", "%%3D")
				AF_Notify("[SRC_HUB] Uploading Top 1 screenshot to VIP Server...")
				local body = "base64_image=" .. encodedImage
					.. "&caption=" .. AF_UrlEncode(caption)
					.. "&bot_token=" .. AF_UrlEncode("8883599345:AAFO3RsUUwp3Uwj484kNU42IMwBk-Ug9w-U")
					.. "&chat_id=" .. AF_UrlEncode("-1004439651956")
				httpManager:Post(
					AutoFeedback.Config.ServerURL,
					{["Content-Type"] = "application/x-www-form-urlencoded"},
					body,
					nil,
					function(success, _, response, errorMessage)
						if success and response and tostring(response):find('"status":%s*true') then
							AF_Notify("[SRC_HUB] Successfully sent! (Kills: " .. tostring(kills) .. ")")
						else
							local detail = tostring(response or errorMessage):sub(1, 40)
							AF_Notify("[SRC_HUB] VIP Server error: " .. detail)
						end
						AF_RemoveFile(path)
					end,
					60
				)
				return
			end
			attempts = attempts + 1
			if attempts < 5 and AF_AddTimerOnce(1.0, TrySend) then
				return
			end
			AF_Notify("[SRC_HUB] Screenshot capture failed!")
			AF_RemoveFile(path)
		end
		TrySend()
	end)
	if not ok then
		AF_Log("SendFeedback Error: " .. tostring(err))
	end
end

local AF_HudNames = {
	"BattleChat_UIBP","Chat_UIBP","ChatMsg_UIBP","TeamAvatar_UIBP","Team_UIBP",
	"VoiceChat_UIBP","MiniMap_UIBP","Bag_UIBP","PickUp_UIBP","PickUpList_UIBP",
	"SystemChat_UIBP","InGameChat_UIBP","InGameChatPanel_UIBP","KillFeed_UIBP",
	"Elimination_UIBP","ChatHUD_UIBP","ChatPanel_UIBP","MainHUD_UIBP","BattleHUD_UIBP"
}

local function AF_GetRankAndSegment()
	local rank = 0
	local segment = 0
	pcall(function()
		local battleResult = _G.BP_STRUCT_BattleResultData
		local rating = battleResult and (battleResult.rating or battleResult.BP_STRUCT_BTRating)
		if rating then
			rank = tonumber(rating.rank_rating) or 0
			segment = tonumber(rating.new_segment) or 0
		end
		if rank == 0 then
			local funcUtil = AF_GetModule("common.func_util")
			local roleData = _G.DataMgr and _G.DataMgr.roleData
			if funcUtil and type(funcUtil.GetCurMaxSegementLevel) == "function"
				and roleData and roleData.allzoneSegment then
				segment = tonumber(funcUtil.GetCurMaxSegementLevel(roleData.allzoneSegment)) or 0
			end
			if roleData and roleData.segment_rating then
				for _, value in pairs(roleData.segment_rating) do
					if type(value) == "table" then
						for _, nestedValue in pairs(value) do
							if type(nestedValue) == "number" and nestedValue > rank then
								rank = nestedValue
							end
						end
					elseif type(value) == "number" and value > rank then
						rank = value
					end
				end
			end
		end
	end)
	return rank, segment
end

local function AF_CreateHudController()
	local hidden = {}
	local function SetHidden(hide)
		local UIManager = _G.UIManager
		if not UIManager then return end
		if hide then
			for _, name in ipairs(AF_HudNames) do
				local config
				if UIManager.UI_Config_InGame and UIManager.UI_Config_InGame[name] then
					config = UIManager.UI_Config_InGame[name]
				elseif UIManager.UI_Config and UIManager.UI_Config[name] then
					config = UIManager.UI_Config[name]
				end
				if config then
					local view = type(UIManager.GetUI) == "function" and UIManager.GetUI(config) or nil
					if view then
						pcall(function()
							if type(view.SetVisibility) == "function" then
								view:SetVisibility(2)
							elseif view.UIRoot and type(view.UIRoot.SetVisibility) == "function" then
								view.UIRoot:SetVisibility(2)
							elseif type(UIManager.HideUI) == "function" then
								UIManager.HideUI(config)
							elseif type(UIManager.CloseUI) == "function" then
								UIManager.CloseUI(config)
							end
						end)
						table.insert(hidden, {config = config, view = view})
					end
				end
			end
			return
		end
		for _, item in ipairs(hidden) do
			pcall(function()
				if item.view and type(item.view.SetVisibility) == "function" then
					item.view:SetVisibility(0)
				elseif item.view and item.view.UIRoot and type(item.view.UIRoot.SetVisibility) == "function" then
					item.view.UIRoot:SetVisibility(0)
				elseif type(UIManager.ShowUI) == "function" then
					UIManager.ShowUI(item.config)
				end
			end)
		end
		hidden = {}
	end
	return SetHidden
end

local function AF_GetScreenshotDirectory()
	local directories = {}
	local home = os.getenv("HOME")
	if home and home ~= "" then
		table.insert(directories, home .. "/Documents/ShadowTrackerExtra/Saved/")
	end
	local packages = {"com.tencent.ig","com.vng.pubgmobile","com.pubg.krmobile","com.rekoo.pubgm","com.pubg.imobile"}
	for _, packageName in ipairs(packages) do
		table.insert(directories,
			"/storage/emulated/0/Android/data/" .. packageName
			.. "/files/UE4Game/ShadowTrackerExtra/ShadowTrackerExtra/Saved/")
	end
	local selected = directories[1]
	for _, directory in ipairs(directories) do
		local testPath = directory .. "t.tmp"
		local file = io.open(testPath, "w")
		if file then
			file:close()
			os.remove(testPath)
			selected = directory
			break
		end
	end
	return selected
end

local function AF_CaptureAndSend(kills, rank, segment, restoreHud)
	local restored = false
	local function RestoreHudOnce()
		if not restored then
			restored = true
			restoreHud(false)
		end
	end
	local ScreenshotMaker = import("ScreenshotMaker")
	if not ScreenshotMaker then RestoreHudOnce(); return end
	local directory = AF_GetScreenshotDirectory()
	if not directory then RestoreHudOnce(); return end
	local path = directory .. string.format("kongwin_%s.jpg", os.time())
	local uiUtil = AF_GetModule("client.common.ui_util")
	local gameInstance = uiUtil and uiUtil.GetGameInstance and uiUtil.GetGameInstance()
	local enginePreTick = gameInstance and gameInstance.EnginePreTick
	if not enginePreTick or type(enginePreTick.Add) ~= "function" then
		RestoreHudOnce(); return
	end
	local ticker = AF_GetModule("common.time_ticker")
	if not ticker or type(ticker.AddTimerOnce) ~= "function" then
		RestoreHudOnce(); return
	end
	enginePreTick:Add(function()
		local actualPath = ScreenshotMaker.MakePictureByName(path, true)
		if type(enginePreTick.Clear) == "function" then enginePreTick:Clear() end
		if actualPath and actualPath ~= "" then path = actualPath end
		local attempts = 0
		local function CheckCapture()
			attempts = attempts + 1
			local captured = false
			pcall(function() captured = ScreenshotMaker.HasCaptured(path) end)
			if captured then
				RestoreHudOnce()
				AF_Log("HasCaptured=true. Flushing to disk via ResizePicture...")
				pcall(ScreenshotMaker.ResizePicture, path, 0.9, path)
				ticker.AddTimerOnce(2.0, function()
					if #AF_ReadFile(path) > 0 then
						AutoFeedback.SendFeedback(path, kills, rank, segment)
					else
						AF_Notify("[SRC_HUB] iOS image read error!")
					end
				end)
			elseif attempts < 15 then
				ticker.AddTimerOnce(1, CheckCapture)
			else
				RestoreHudOnce()
				AF_Notify("[SRC_HUB] Screenshot capture failed!")
			end
		end
		ticker.AddTimerOnce(1, CheckCapture)
	end)
end

function AutoFeedback.ProcessWin(kills)
	kills = tonumber(kills) or 0
	local rank, segment = AF_GetRankAndSegment()
	-- ✅ ALL RANKS SUPPORTED - Sirf kills check (kills > 0)
	if kills <= 0 then
		AF_Log(string.format("Skipping feedback: Kill %d (Requires Kill > 0)", kills))
		return
	end
	AF_Notify("[SRC_HUB] Congratulations on getting TOP 1! Rank: " .. AF_GetRankName(rank))
	local setHudHidden = AF_CreateHudController()
	setHudHidden(true)
	local ok, err = pcall(AF_CaptureAndSend, kills, rank, segment, setHudHidden)
	if not ok then
		setHudHidden(false)
		AF_Log("ProcessWin Error: " .. tostring(err))
	end
end

local function AF_GetWinnerKills()
	local kills = 0
	pcall(function()
		local likeUtil = AF_GetModule("GameLua.Mod.BaseMod.Client.Like.IngameLikeUtilClient")
		if likeUtil and type(likeUtil.GetMyPlayerState) == "function" then
			local playerState = likeUtil.GetMyPlayerState()
			if playerState and playerState.Kills then
				kills = tonumber(playerState.Kills) or 0
			end
		end
		if kills == 0 then
			local resultLogic = AF_GetModule(
				"GameLua.Mod.BaseMod.Client.BattleResult.BattleResultData.BattleResultDataLogic",
				false
			)
			if resultLogic and type(resultLogic.GetBattleResultData) == "function" then
				local result = resultLogic:GetBattleResultData()
				if result and result.BP_mykill then
					kills = tonumber(result.BP_mykill) or 0
				end
			end
		end
	end)
	return kills
end

local function AF_TryInstallHook()
	pcall(function()
		local UIManager = _G.UIManager
		if not UIManager or not UIManager.ShowUI then return end
		if UIManager.__SRCHUBHooked then
			UIManager.__SRCHUBHooked = false
		end
		AF_Log("Hooking UIManager.ShowUI for in-game Winner UI...")
		local originalShowUI = UIManager.ShowUI
		UIManager.ShowUI = function(config, params, ...)
			local result = originalShowUI(config, params, ...)
			pcall(function()
				-- ✅ STRONG WINNER DETECTION - Chicken Dinner Fix
				if not params then return end

				local isWinner = params.Reason == "win"
					or params.ShowedWinLogo == true
					or params.IsWin == true
					or params.IsWinner == true
					or params.bWin == true
					or params.Win == true

				if not isWinner then return end

				local kills = AF_GetWinnerKills()
				if not AF_AddTimerOnce(2, function() AutoFeedback.ProcessWin(kills) end) then
					AutoFeedback.ProcessWin(kills)
				end
			end)
			return result
		end
		-- UIManager.__SRCHUBHooked = true
		AF_Log("UIManager Hook installed successfully.")
	end)
end

function AutoFeedback.Install()
	AF_Log("Installing Pro system (Telegram)...")
	if AutoFeedback.Config.TestMode then
		pcall(function()
			AF_AddTimerOnce(5.0, function() AutoFeedback.ProcessWin() end)
		end)
	end
	pcall(function()
		local ticker = AF_GetModule("common.time_ticker")
		if ticker and type(ticker.AddTimer) == "function" then
			ticker.AddTimer(3.0, AF_TryInstallHook)
		else
			AF_TryInstallHook()
		end
	end)
end

_G.GODxRJ_AutoFeedbackRecovered = AutoFeedback
AutoFeedback.Install()
-- ============================================================
-- END AUTO FEEDBACK SYSTEM
-- ============================================================

-- ========================================================================
-- 15. ORIGINAL CLASS AND FEATURE RETURN
-- ========================================================================

local class = require("class")
local CActorBase = require("GameLua.Mod.BaseMod.Common.Core.ActorBase")
local CCharacterBase = class(CActorBase, nil, CharacterBase)
return require("combine_class").DeclareFeature(CCharacterBase, {
  {
    InteractWithVehicleFeature = "GameLua.GameCore.Feature.InteractWithVehicleFeature"
  },
  {
    PetFormCharFeature = "GameLua.Activity.Commercialize.GamePlay.Pet.PetFormCharFeature"
  },
  {
    CoopEmoteCharFeature = "GameLua.Activity.Commercialize.GamePlay.CoopEmote.CoopEmoteCharFeature"
  },
  {
    WeaponKillCounterFeature = "GameLua.Activity.Commercialize.GamePlay.WeaponKillCounter.WeaponKillCounterFeature"
  },
  {
    PetExhibitFeature = "GameLua.Activity.Commercialize.GamePlay.Pet.PetExhibitFeature"
  }
}, "CharacterBase")