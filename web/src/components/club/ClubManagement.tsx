import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { AppControls } from "../../App";
import { fetchNui } from "../../providers/nui/fetchNui";
import { useNuiEvent } from "../../providers/nui/useNui";
import { Button } from "../ui/button";

type Vec3 = { x: number; y: number; z: number };
type ViewMode = "clubsRoot" | "clubDetail" | "entityDetail";

type ClubJob = { name: string; primary: boolean };

type BartenderEntity = {
  type: "bartender";
  bartender: {
    coords?: Vec3;
    heading?: number;
    blip?: {
      name?: string;
      color?: number;
      sprite?: number;
      scale?: number;
      visible?: boolean;
    };
  };
};

type BouncerEntity = {
  type: "bouncer";
  bouncer: {
    ped: string;
    coords?: Vec3;
    heading?: number;
  };
};

type ClubEntryEntity = {
  type: "club_entry";
  bouncer: {
    ped: string;
    coords?: Vec3;
    heading?: number;
  };
  eject: {
    coords?: Vec3;
    heading?: number;
  };
};

type SocietyEntity = {
  type: "society";
  society: {
    coords?: Vec3;
    heading?: number;
  };
};

type ClubEntity = BartenderEntity | BouncerEntity | ClubEntryEntity | SocietyEntity | Record<string, unknown>;

interface ClubSummary {
  id: number;
  label: string;
  description?: string;
  coords?: Vec3;
  society_percentage?: number;
  jobs?: ClubJob[];
  entities?: Record<string, ClubEntity>;
}

interface ClubManagementData {
  clubs?: ClubSummary[];
}

interface ClubEditorState {
  label: string;
  description: string;
  coords: Vec3;
  society_percentage: number;
  jobs: ClubJob[];
}

interface EntityEditorState {
  type: "bartender" | "bouncer" | "club_entry" | "society";
  bartender: {
    coords: Vec3;
    heading: number;
    blipName: string;
    blipColor: number;
    blipSprite: number;
    blipScale: number;
    blipVisible: boolean;
  };
  bouncer: {
    ped: string;
    coords: Vec3;
    heading: number;
  };
  clubEntry: {
    ped: string;
    bouncerCoords: Vec3;
    bouncerHeading: number;
    ejectCoords: Vec3;
    ejectHeading: number;
  };
  society: {
    coords: Vec3;
    heading: number;
  };
}

const DEFAULT_VEC3: Vec3 = { x: 0, y: 0, z: 0 };

function toVec3(value: unknown, fallback: Vec3 = DEFAULT_VEC3): Vec3 {
  if (!value || typeof value !== "object") return fallback;
  const obj = value as { x?: number; y?: number; z?: number };
  if (typeof obj.x !== "number" || typeof obj.y !== "number" || typeof obj.z !== "number") {
    return fallback;
  }
  return { x: obj.x, y: obj.y, z: obj.z };
}

function formatCoords(coords?: Vec3): string {
  if (!coords) return "—";
  return `(${coords.x.toFixed(2)}, ${coords.y.toFixed(2)}, ${coords.z.toFixed(2)})`;
}

function formatHeading(heading?: number): string {
  if (typeof heading !== "number") return "—";
  return heading.toFixed(2);
}

function normalizeClubs(raw: ClubSummary[]): ClubSummary[] {
  return (raw || []).map((club) => ({
    id: club.id,
    label: club.label || `Club #${club.id}`,
    description: club.description || "",
    coords: toVec3(club.coords, DEFAULT_VEC3),
    society_percentage: typeof club.society_percentage === "number" ? club.society_percentage : 0,
    jobs: Array.isArray(club.jobs) ? club.jobs : [],
    entities: club.entities || {},
  }));
}

function createClubDraft(club?: ClubSummary): ClubEditorState {
  const jobs = Array.isArray(club?.jobs) ? club.jobs : [];
  return {
    label: club?.label || "",
    description: club?.description || "",
    coords: toVec3(club?.coords, DEFAULT_VEC3),
    society_percentage: typeof club?.society_percentage === "number" ? club.society_percentage : 0,
    jobs: jobs.length ? jobs : [],
  };
}

function createEmptyEntityDraft(): EntityEditorState {
  return {
    type: "bartender",
    bartender: {
      coords: { ...DEFAULT_VEC3 },
      heading: 0,
      blipName: "Bartending Station",
      blipColor: 5,
      blipSprite: 52,
      blipScale: 0.8,
      blipVisible: true,
    },
    bouncer: {
      ped: "bouncer_1",
      coords: { ...DEFAULT_VEC3 },
      heading: 0,
    },
    clubEntry: {
      ped: "bouncer_1",
      bouncerCoords: { ...DEFAULT_VEC3 },
      bouncerHeading: 0,
      ejectCoords: { ...DEFAULT_VEC3 },
      ejectHeading: 0,
    },
    society: {
      coords: { ...DEFAULT_VEC3 },
      heading: 0,
    },
  };
}

function createEntityDraft(club: ClubSummary, entityId?: string): EntityEditorState {
  const base = createEmptyEntityDraft();
  if (!entityId || !club.entities || !club.entities[entityId]) {
    const center = toVec3(club.coords, DEFAULT_VEC3);
    base.bartender.coords = { ...center };
    base.bouncer.coords = { ...center };
    base.clubEntry.bouncerCoords = { ...center };
    base.clubEntry.ejectCoords = { ...center };
    base.society.coords = { ...center };
    return base;
  }

  const entity = club.entities[entityId] as Record<string, unknown>;
  const entityType =
    entity.type === "bartender" || entity.type === "bouncer" || entity.type === "club_entry" || entity.type === "society"
      ? entity.type
      : "bartender";
  base.type = entityType;

  if (entityType === "bartender") {
    const bartender = (entity.bartender || {}) as Record<string, unknown>;
    const blip = (bartender.blip || {}) as Record<string, unknown>;
    base.bartender.coords = toVec3(bartender.coords, toVec3(club.coords, DEFAULT_VEC3));
    base.bartender.heading = typeof bartender.heading === "number" ? bartender.heading : 0;
    base.bartender.blipName = typeof blip.name === "string" ? blip.name : "Bartending Station";
    base.bartender.blipColor = typeof blip.color === "number" ? blip.color : 5;
    base.bartender.blipSprite = typeof blip.sprite === "number" ? blip.sprite : 52;
    base.bartender.blipScale = typeof blip.scale === "number" ? blip.scale : 0.8;
    base.bartender.blipVisible = blip.visible !== false;
  } else if (entityType === "bouncer") {
    const bouncer = (entity.bouncer || {}) as Record<string, unknown>;
    base.bouncer.ped = typeof bouncer.ped === "string" ? bouncer.ped : "bouncer_1";
    base.bouncer.coords = toVec3(bouncer.coords, toVec3(club.coords, DEFAULT_VEC3));
    base.bouncer.heading = typeof bouncer.heading === "number" ? bouncer.heading : 0;
  } else if (entityType === "club_entry") {
    const bouncer = (entity.bouncer || {}) as Record<string, unknown>;
    const eject = (entity.eject || {}) as Record<string, unknown>;
    base.clubEntry.ped = typeof bouncer.ped === "string" ? bouncer.ped : "bouncer_1";
    base.clubEntry.bouncerCoords = toVec3(bouncer.coords, toVec3(club.coords, DEFAULT_VEC3));
    base.clubEntry.bouncerHeading = typeof bouncer.heading === "number" ? bouncer.heading : 0;
    base.clubEntry.ejectCoords = toVec3(eject.coords, toVec3(club.coords, DEFAULT_VEC3));
    base.clubEntry.ejectHeading = typeof eject.heading === "number" ? eject.heading : 0;
  } else if (entityType === "society") {
    const society = (entity.society || {}) as Record<string, unknown>;
    base.society.coords = toVec3(society.coords, toVec3(club.coords, DEFAULT_VEC3));
    base.society.heading = typeof society.heading === "number" ? society.heading : 0;
  }
  return base;
}

function getEntityEntries(club?: ClubSummary): { id: string; type: string }[] {
  if (!club || !club.entities) return [];
  return Object.entries(club.entities)
    .map(([id, entity]) => ({
      id,
      type: (entity as { type?: string }).type || "unknown",
    }))
    .sort((a, b) => a.id.localeCompare(b.id));
}

function NumericInput({
  value,
  onChange,
  step = "0.01",
}: {
  value: number;
  onChange: (value: number) => void;
  step?: string;
}) {
  return (
    <input
      type="number"
      step={step}
      value={Number.isFinite(value) ? value : 0}
      onChange={(e) => onChange(Number(e.target.value))}
      className="w-full h-9 rounded-md border border-border bg-background px-2 text-sm"
    />
  );
}

function ReadOnlyTransform({
  label,
  coords,
  heading,
}: {
  label: string;
  coords?: Vec3;
  heading?: number;
}) {
  return (
    <div className="rounded-md border border-border bg-background px-2 py-2 text-xs">
      <div className="font-semibold">{label}</div>
      <div className="text-muted-foreground">Coords: {formatCoords(coords)}</div>
      <div className="text-muted-foreground">Heading: {formatHeading(heading)}</div>
    </div>
  );
}

export function ClubManagement() {
  const [visible, setVisible] = useState(false);
  const [hidden, setHidden] = useState(true);
  const [panelHiddenForGizmo, setPanelHiddenForGizmo] = useState(false);
  const [focus, setFocus] = useState(true);
  const [view, setView] = useState<ViewMode>("clubsRoot");
  const [busyAction, setBusyAction] = useState(false);
  const [clubs, setClubs] = useState<ClubSummary[]>([]);
  const [selectedClubId, setSelectedClubId] = useState<number | null>(null);
  const [selectedEntityId, setSelectedEntityId] = useState<string | null>(null);
  const [creatingClub, setCreatingClub] = useState(false);
  const [creatingEntity, setCreatingEntity] = useState(false);
  const [clubDraft, setClubDraft] = useState<ClubEditorState>(createClubDraft());
  const [entityDraft, setEntityDraft] = useState<EntityEditorState>(createEmptyEntityDraft());
  const [newJobName, setNewJobName] = useState("");
  const openTimerRef = useRef<number | null>(null);
  const closeTimerRef = useRef<number | null>(null);

  const selectedClub = useMemo(
    () => (selectedClubId != null ? clubs.find((c) => c.id === selectedClubId) || null : null),
    [clubs, selectedClubId]
  );

  const entityEntries = useMemo(() => getEntityEntries(selectedClub || undefined), [selectedClub]);

  const clearTimers = useCallback(() => {
    if (openTimerRef.current) {
      window.clearTimeout(openTimerRef.current);
      openTimerRef.current = null;
    }
    if (closeTimerRef.current) {
      window.clearTimeout(closeTimerRef.current);
      closeTimerRef.current = null;
    }
  }, []);

  const resetState = useCallback(() => {
    setClubs([]);
    setView("clubsRoot");
    setSelectedClubId(null);
    setSelectedEntityId(null);
    setCreatingClub(false);
    setCreatingEntity(false);
    setBusyAction(false);
    setClubDraft(createClubDraft());
    setEntityDraft(createEmptyEntityDraft());
  }, []);

  const startOpenTransition = useCallback(() => {
    clearTimers();
    setVisible(true);
    setHidden(true);
    openTimerRef.current = window.setTimeout(() => {
      setHidden(false);
      openTimerRef.current = null;
    }, 25);
  }, [clearTimers]);

  const startCloseTransition = useCallback(() => {
    clearTimers();
    setHidden(true);
    closeTimerRef.current = window.setTimeout(() => {
      setVisible(false);
      resetState();
      closeTimerRef.current = null;
    }, 300);
  }, [clearTimers, resetState]);

  const sendClubAction = useCallback(
    (action: string, data: Record<string, unknown>) => fetchNui("clubManagementAction", { action, data }),
    []
  );

  const withBusyAction = useCallback(
    async (cb: () => Promise<void>) => {
      setBusyAction(true);
      try {
        await cb();
      } finally {
        setBusyAction(false);
      }
    },
    []
  );

  const openCreateClub = () => {
    setCreatingClub(true);
    setSelectedClubId(null);
    setClubDraft(createClubDraft());
    setView("clubDetail");
  };

  const openClubDetail = (clubId: number) => {
    const club = clubs.find((c) => c.id === clubId);
    setCreatingClub(false);
    setSelectedClubId(clubId);
    setClubDraft(createClubDraft(club));
    setSelectedEntityId(null);
    setCreatingEntity(false);
    setEntityDraft(createEmptyEntityDraft());
    setView("clubDetail");
  };

  const backToClubsRoot = () => {
    setView("clubsRoot");
    setCreatingClub(false);
    setSelectedClubId(null);
    setSelectedEntityId(null);
    setCreatingEntity(false);
    setEntityDraft(createEmptyEntityDraft());
  };

  const openCreateEntity = () => {
    if (!selectedClub) return;
    setCreatingEntity(true);
    setSelectedEntityId(null);
    setEntityDraft(createEntityDraft(selectedClub));
    setView("entityDetail");
  };

  const openEntityDetail = (entityId: string) => {
    if (!selectedClub) return;
    setCreatingEntity(false);
    setSelectedEntityId(entityId);
    setEntityDraft(createEntityDraft(selectedClub, entityId));
    setView("entityDetail");
  };

  const backToClubDetail = () => {
    setView("clubDetail");
    setCreatingEntity(false);
    setSelectedEntityId(null);
    setEntityDraft(createEmptyEntityDraft());
  };

  useNuiEvent("openClubManagement", (data: ClubManagementData & { clubId?: number; entityId?: string }) => {
    const nextClubs = normalizeClubs(data.clubs || []);
    setClubs(nextClubs);
    setCreatingClub(false);
    setClubDraft(createClubDraft());
    setEntityDraft(createEmptyEntityDraft());
    const clubId = data.clubId != null ? Number(data.clubId) : null;
    const entityId = typeof data.entityId === "string" ? data.entityId : null;
    if (clubId != null && entityId != null) {
      const club = nextClubs.find((c) => c.id === clubId);
      if (club && club.entities?.[entityId]) {
        setSelectedClubId(clubId);
        setSelectedEntityId(entityId);
        setCreatingEntity(false);
        setClubDraft(createClubDraft(club));
        setEntityDraft(createEntityDraft(club, entityId));
        setView("entityDetail");
      } else {
        setView("clubsRoot");
        setSelectedClubId(null);
        setSelectedEntityId(null);
      }
    } else {
      setView("clubsRoot");
      setSelectedClubId(null);
      setSelectedEntityId(null);
      setCreatingEntity(false);
    }
    startOpenTransition();
  });

  useNuiEvent("setClubManagementFocus", (data: { toggle?: boolean }) => {
    setFocus(data.toggle !== false);
  });

  useNuiEvent("updateClubManagement", (data: ClubManagementData) => {
    setClubs(normalizeClubs(data.clubs || []));
  });

  useEffect(() => {
    if (view !== "entityDetail" || creatingEntity || selectedClubId == null || selectedEntityId == null) return;
    const club = clubs.find((c) => c.id === selectedClubId);
    if (!club) return;
    setEntityDraft(createEntityDraft(club, selectedEntityId));
  }, [clubs, view, creatingEntity, selectedClubId, selectedEntityId]);

  useNuiEvent("setClubManagementHidden", () => {
    startCloseTransition();
  });

  useNuiEvent("setClubManagementPanelHidden", (data: { hidden?: boolean }) => {
    setPanelHiddenForGizmo(data.hidden === true);
  });

  const handleClose = useCallback(() => {
    fetchNui("closeClubManagement", {});
    startCloseTransition();
  }, [startCloseTransition]);

  const saveClub = async () => {
    if (!clubDraft.label.trim()) return;
    const payload = {
      label: clubDraft.label.trim(),
      description: clubDraft.description,
      society_percentage: Math.max(0, Math.min(100, clubDraft.society_percentage)),
      jobs: clubDraft.jobs,
    };
    await withBusyAction(async () => {
      if (creatingClub) {
        await sendClubAction("createClub", payload);
        backToClubsRoot();
        return;
      }
      if (selectedClubId == null) return;
      await sendClubAction("updateClub", {
        clubId: selectedClubId,
        ...payload,
      });
    });
  };

  const setClubJobsPrimary = (index: number) => {
    if (selectedClubId == null) return;
    const next = clubDraft.jobs.map((j, i) => ({ ...j, primary: i === index }));
    setClubDraft((prev) => ({ ...prev, jobs: next }));
    sendClubAction("updateClub", { clubId: selectedClubId, jobs: next });
  };

  const addClubJob = (jobName: string) => {
    const next = [...clubDraft.jobs, { name: jobName, primary: clubDraft.jobs.length === 0 }];
    setClubDraft((prev) => ({ ...prev, jobs: next }));
    if (selectedClubId != null) {
      sendClubAction("updateClub", { clubId: selectedClubId, jobs: next });
    }
  };

  const removeClubJob = (index: number) => {
    const next = clubDraft.jobs.filter((_, i) => i !== index);
    const hadPrimary = clubDraft.jobs[index]?.primary;
    if (hadPrimary && next.length > 0 && !next.some((j) => j.primary)) {
      next[0] = { ...next[0], primary: true };
    }
    setClubDraft((prev) => ({ ...prev, jobs: next }));
    if (selectedClubId != null) {
      sendClubAction("updateClub", { clubId: selectedClubId, jobs: next });
    }
  };

  const editClubCoordsWithGizmo = async () => {
    if (selectedClubId == null) return;
    await withBusyAction(async () => {
      await sendClubAction("editClubCoords", { clubId: selectedClubId });
    });
  };

  const deleteClub = async () => {
    if (selectedClubId == null) return;
    await withBusyAction(async () => {
      await sendClubAction("deleteClub", { clubId: selectedClubId });
      backToClubsRoot();
    });
  };

  function buildEntityPayloadFromDraft(draft: EntityEditorState, includeTransform: boolean): ClubEntity | null {
    if (draft.type === "bartender") {
      const base: ClubEntity = {
        type: "bartender",
        bartender: {
          blip: {
            name: draft.bartender.blipName,
            color: draft.bartender.blipColor,
            sprite: draft.bartender.blipSprite,
            scale: draft.bartender.blipScale,
            visible: draft.bartender.blipVisible,
          },
        },
      };
      if (includeTransform) {
        (base as BartenderEntity).bartender.coords = draft.bartender.coords;
        (base as BartenderEntity).bartender.heading = draft.bartender.heading;
      }
      return base;
    }
    if (draft.type === "bouncer") {
      if (!draft.bouncer.ped.trim()) return null;
      const base: ClubEntity = {
        type: "bouncer",
        bouncer: { ped: draft.bouncer.ped.trim() },
      };
      if (includeTransform) {
        (base as BouncerEntity).bouncer.coords = draft.bouncer.coords;
        (base as BouncerEntity).bouncer.heading = draft.bouncer.heading;
      }
      return base;
    }
    if (draft.type === "club_entry") {
      if (!draft.clubEntry.ped.trim()) return null;
      const base: ClubEntity = {
        type: "club_entry",
        bouncer: { ped: draft.clubEntry.ped.trim() },
        eject: {},
      };
      if (includeTransform) {
        (base as ClubEntryEntity).bouncer.coords = draft.clubEntry.bouncerCoords;
        (base as ClubEntryEntity).bouncer.heading = draft.clubEntry.bouncerHeading;
        (base as ClubEntryEntity).eject.coords = draft.clubEntry.ejectCoords;
        (base as ClubEntryEntity).eject.heading = draft.clubEntry.ejectHeading;
      }
      return base;
    }
    if (draft.type === "society") {
      const base: ClubEntity = {
        type: "society",
        society: {},
      };
      if (includeTransform) {
        (base as SocietyEntity).society.coords = draft.society.coords;
        (base as SocietyEntity).society.heading = draft.society.heading;
      }
      return base;
    }
    return null;
  }

  const entityDraftRef = useRef<EntityEditorState>(entityDraft);
  entityDraftRef.current = entityDraft;

  const debouncedEntitySaveRef = useRef<number | null>(null);
  const DEBOUNCE_MS = 500;

  const scheduleEntitySave = useCallback(() => {
    if (creatingEntity || selectedClubId == null || selectedEntityId == null) return;
    if (debouncedEntitySaveRef.current != null) {
      window.clearTimeout(debouncedEntitySaveRef.current);
    }
    debouncedEntitySaveRef.current = window.setTimeout(() => {
      debouncedEntitySaveRef.current = null;
      const draft = entityDraftRef.current;
      const payload = buildEntityPayloadFromDraft(draft, true);
      if (payload) {
        sendClubAction("updateClubEntity", {
          clubId: selectedClubId,
          entityId: selectedEntityId,
          entityData: payload,
        });
      }
    }, DEBOUNCE_MS);
  }, [creatingEntity, selectedClubId, selectedEntityId, sendClubAction]);

  const createEntity = async () => {
    if (selectedClubId == null || !creatingEntity) return;
    const payload = buildEntityPayloadFromDraft(entityDraft, false);
    if (!payload) return;
    await withBusyAction(async () => {
      await sendClubAction("createClubEntity", {
        clubId: selectedClubId,
        entityType: entityDraft.type,
        entityData: payload,
        useGizmo: true,
      });
      backToClubDetail();
    });
  };

  const editEntityTransform = async (target: "main" | "bouncer" | "eject") => {
    if (selectedClubId == null || !selectedEntityId) return;
    await withBusyAction(async () => {
      await sendClubAction("editEntityTransform", {
        clubId: selectedClubId,
        entityId: selectedEntityId,
        target,
      });
    });
  };

  const deleteEntity = async () => {
    if (selectedClubId == null || !selectedEntityId) return;
    await withBusyAction(async () => {
      await sendClubAction("deleteClubEntity", {
        clubId: selectedClubId,
        entityId: selectedEntityId,
      });
      backToClubDetail();
    });
  };

  useEffect(() => {
    if (!visible) return;
    const onKeyDown = (event: KeyboardEvent) => {
      if (panelHiddenForGizmo) return;
      const target = event.target as HTMLElement | null;
      const isTyping =
        target instanceof HTMLInputElement ||
        target instanceof HTMLTextAreaElement ||
        target?.isContentEditable;
      if (isTyping) return;
      if (event.key === "g" || event.key === "G") {
        fetchNui("toggleClubManagementFocus", {});
        return;
      }
      if (event.key === "Escape") {
        handleClose();
        return;
      }
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [visible, handleClose, panelHiddenForGizmo]);

  useEffect(() => {
    return () => clearTimers();
  }, [clearTimers]);

  useEffect(() => {
    return () => {
      if (debouncedEntitySaveRef.current != null) {
        window.clearTimeout(debouncedEntitySaveRef.current);
      }
    };
  }, []);

  if (!visible) return null;

  return (
    <div className="fixed inset-0 z-[100] text-primary">
      {!panelHiddenForGizmo && (
        <AppControls
          controls={[
            { key: "ESC", label: "Exit" },
            { key: "G", label: `Focus ${focus ? "Off" : "On"}` },
          ]}
        />
      )}
      <div
        className={`absolute top-0 right-0 h-full w-[430px] bg-background/95 border-l border-border flex flex-col transition-transform duration-300 ${
          hidden || panelHiddenForGizmo ? "translate-x-full" : "translate-x-0"
        }`}
      >
        <div className="p-3 border-b border-border flex items-center justify-between">
          <div>
            <div className="text-lg font-semibold">Club Management</div>
            <div className="text-xs text-muted-foreground">
              {view === "clubsRoot" && "Clubs"}
              {view === "clubDetail" && "Club Configuration + Entities"}
              {view === "entityDetail" && "Entity Configuration"}
            </div>
          </div>
          <Button variant="outline" size="sm" onClick={handleClose}>
            Close
          </Button>
        </div>

        <div className="flex-1 overflow-auto p-3 space-y-3">
          {view === "clubsRoot" && (
            <div className="space-y-2">
              <div className="flex items-center justify-between">
                <div className="text-sm font-semibold">Clubs</div>
                <Button size="sm" variant="secondary" onClick={openCreateClub} disabled={busyAction}>
                  New Club
                </Button>
              </div>
              <div className="space-y-1 max-h-[70vh] overflow-auto">
                {clubs.length === 0 && (
                  <div className="text-xs text-muted-foreground">No clubs found.</div>
                )}
                {clubs.map((club) => (
                  <button
                    key={club.id}
                    type="button"
                    onClick={() => openClubDetail(club.id)}
                    className="w-full rounded-md px-2 py-2 text-left text-sm bg-secondary hover:bg-secondary/80"
                  >
                    <div className="font-semibold">#{club.id} {club.label}</div>
                    <div className="text-[11px] text-muted-foreground">{formatCoords(club.coords)}</div>
                  </button>
                ))}
              </div>
            </div>
          )}

          {view === "clubDetail" && (
            <div className="space-y-2">
              <Button size="sm" variant="outline" onClick={backToClubsRoot} disabled={busyAction}>
                Back To Clubs
              </Button>
              <div className="rounded-md border border-border bg-secondary/30 p-2 space-y-2">
                <div className="text-sm font-semibold">
                  {creatingClub ? "Create Club" : `Edit Club #${selectedClubId ?? "?"}`}
                </div>
                <input
                  type="text"
                  value={clubDraft.label}
                  onChange={(e) => setClubDraft((prev) => ({ ...prev, label: e.target.value }))}
                  className="w-full h-9 rounded-md border border-border bg-background px-2 text-sm"
                  placeholder="Club label"
                />
                <textarea
                  value={clubDraft.description}
                  onChange={(e) => setClubDraft((prev) => ({ ...prev, description: e.target.value }))}
                  className="w-full rounded-md border border-border bg-background p-2 text-sm min-h-20"
                  placeholder="Description"
                />
                <div className="space-y-1">
                  <div className="text-xs font-medium text-muted-foreground">Business (payouts use primary job as society)</div>
                  <div className="flex items-center gap-2">
                    <span className="text-xs text-muted-foreground">Society %</span>
                    <NumericInput
                      value={clubDraft.society_percentage}
                      onChange={(v) => setClubDraft((prev) => ({ ...prev, society_percentage: Math.max(0, Math.min(100, v)) }))}
                      step="1"
                    />
                  </div>
                </div>
                <div className="space-y-1">
                  <div className="text-xs font-medium text-muted-foreground">Jobs with access (one primary)</div>
                  {clubDraft.jobs.length === 0 && (
                    <div className="text-xs text-muted-foreground">No jobs. Add one below.</div>
                  )}
                  {clubDraft.jobs.map((job, idx) => (
                    <div key={idx} className="flex items-center gap-2 rounded border border-border bg-background px-2 py-1 text-sm">
                      <span className="flex-1 font-mono">{job.name}</span>
                      <label className="flex items-center gap-1 text-xs">
                        <input
                          type="checkbox"
                          checked={job.primary}
                          onChange={() => setClubJobsPrimary(idx)}
                          disabled={busyAction}
                        />
                        Primary
                      </label>
                      <Button
                        type="button"
                        size="sm"
                        variant="ghost"
                        className="h-6 px-1 text-destructive"
                        onClick={() => removeClubJob(idx)}
                        disabled={busyAction}
                      >
                        Remove
                      </Button>
                    </div>
                  ))}
                  <div className="flex gap-2">
                    <input
                      type="text"
                      value={newJobName}
                      onChange={(e) => setNewJobName(e.target.value)}
                      onKeyDown={(e) => {
                        if (e.key === "Enter") {
                          e.preventDefault();
                          const name = newJobName.trim();
                          if (name && !clubDraft.jobs.some((j) => j.name === name)) {
                            addClubJob(name);
                            setNewJobName("");
                          }
                        }
                      }}
                      className="flex-1 h-9 rounded-md border border-border bg-background px-2 text-sm"
                      placeholder="Job name"
                    />
                    <Button
                      type="button"
                      size="sm"
                      variant="secondary"
                      onClick={() => {
                        const name = newJobName.trim();
                        if (name && !clubDraft.jobs.some((j) => j.name === name)) {
                          addClubJob(name);
                          setNewJobName("");
                        }
                      }}
                      disabled={busyAction || !newJobName.trim()}
                    >
                      Add
                    </Button>
                  </div>
                </div>
                {!creatingClub && (
                  <>
                    <div className="text-xs text-muted-foreground">Center: {formatCoords(clubDraft.coords)}</div>
                    <Button size="sm" variant="secondary" onClick={editClubCoordsWithGizmo} disabled={busyAction}>
                      Set Club Center (Gizmo)
                    </Button>
                  </>
                )}
                <div className="flex gap-2">
                  <Button size="sm" onClick={saveClub} disabled={busyAction}>
                    {creatingClub ? "Create Club" : "Save Club"}
                  </Button>
                  {!creatingClub && (
                    <Button size="sm" variant="destructive" onClick={deleteClub} disabled={busyAction}>
                      Delete Club
                    </Button>
                  )}
                </div>
              </div>

              {!creatingClub && selectedClub && (
                <div className="rounded-md border border-border bg-secondary/30 p-2 space-y-2">
                  <div className="flex items-center justify-between">
                    <div className="text-sm font-semibold">Entities</div>
                    <Button size="sm" variant="secondary" onClick={openCreateEntity} disabled={busyAction}>
                      New Entity
                    </Button>
                  </div>
                  <div className="space-y-1 max-h-[36vh] overflow-auto">
                    {entityEntries.length === 0 && (
                      <div className="text-xs text-muted-foreground">No entities in this club.</div>
                    )}
                    {entityEntries.map((entity) => (
                      <button
                        key={entity.id}
                        type="button"
                        onClick={() => openEntityDetail(entity.id)}
                        className="w-full rounded-md px-2 py-2 text-left text-xs bg-secondary hover:bg-secondary/80"
                      >
                        <div className="font-mono">{entity.id}</div>
                        <div className="text-muted-foreground">{entity.type}</div>
                      </button>
                    ))}
                  </div>
                </div>
              )}
            </div>
          )}

          {view === "entityDetail" && (
            <div className="space-y-2">
              <Button size="sm" variant="outline" onClick={backToClubDetail} disabled={busyAction}>
                Back To Club
              </Button>
              <div className="rounded-md border border-border bg-secondary/30 p-2 space-y-2">
                <div className="text-sm font-semibold">
                  {creatingEntity ? "Create Entity" : `Edit Entity ${selectedEntityId}`}
                </div>
                {creatingEntity && (
                  <select
                    className="w-full h-9 rounded-md border border-border bg-background px-2 text-sm"
                    value={entityDraft.type}
                    onChange={(e) =>
                      setEntityDraft((prev) => ({
                        ...prev,
                        type: e.target.value as EntityEditorState["type"],
                      }))
                    }
                  >
                    <option value="bartender">bartender</option>
                    <option value="bouncer">bouncer</option>
                    <option value="club_entry">club_entry</option>
                    <option value="society">society</option>
                  </select>
                )}

                {entityDraft.type === "bartender" && (
                  <div className="space-y-2">
                    {!creatingEntity && (
                      <>
                        <ReadOnlyTransform
                          label="Position"
                          coords={entityDraft.bartender.coords}
                          heading={entityDraft.bartender.heading}
                        />
                        <Button
                          size="sm"
                          variant="secondary"
                          onClick={() => editEntityTransform("main")}
                          disabled={busyAction}
                        >
                          Move Position (Gizmo)
                        </Button>
                      </>
                    )}
                    <input
                      type="text"
                      value={entityDraft.bartender.blipName}
                      onChange={(e) => {
                        setEntityDraft((prev) => ({
                          ...prev,
                          bartender: { ...prev.bartender, blipName: e.target.value },
                        }));
                        scheduleEntitySave();
                      }}
                      className="w-full h-9 rounded-md border border-border bg-background px-2 text-sm"
                      placeholder="Blip name"
                    />
                    <div className="grid grid-cols-2 gap-2">
                      <NumericInput
                        value={entityDraft.bartender.blipColor}
                        onChange={(blipColor) => {
                          setEntityDraft((prev) => ({ ...prev, bartender: { ...prev.bartender, blipColor } }));
                          scheduleEntitySave();
                        }}
                        step="1"
                      />
                      <NumericInput
                        value={entityDraft.bartender.blipSprite}
                        onChange={(blipSprite) => {
                          setEntityDraft((prev) => ({ ...prev, bartender: { ...prev.bartender, blipSprite } }));
                          scheduleEntitySave();
                        }}
                        step="1"
                      />
                    </div>
                    <NumericInput
                      value={entityDraft.bartender.blipScale}
                      onChange={(blipScale) => {
                        setEntityDraft((prev) => ({ ...prev, bartender: { ...prev.bartender, blipScale } }));
                        scheduleEntitySave();
                      }}
                    />
                    <label className="flex items-center gap-2 text-sm">
                      <input
                        type="checkbox"
                        checked={entityDraft.bartender.blipVisible}
                        onChange={(e) => {
                          setEntityDraft((prev) => ({
                            ...prev,
                            bartender: { ...prev.bartender, blipVisible: e.target.checked },
                          }));
                          scheduleEntitySave();
                        }}
                      />
                      Blip visible
                    </label>
                  </div>
                )}

                {entityDraft.type === "bouncer" && (
                  <div className="space-y-2">
                    {!creatingEntity && (
                      <>
                        <ReadOnlyTransform
                          label="Position"
                          coords={entityDraft.bouncer.coords}
                          heading={entityDraft.bouncer.heading}
                        />
                        <Button
                          size="sm"
                          variant="secondary"
                          onClick={() => editEntityTransform("main")}
                          disabled={busyAction}
                        >
                          Move Position (Gizmo)
                        </Button>
                      </>
                    )}
                    <input
                      type="text"
                      value={entityDraft.bouncer.ped}
                      onChange={(e) => {
                        setEntityDraft((prev) => ({
                          ...prev,
                          bouncer: { ...prev.bouncer, ped: e.target.value },
                        }));
                        scheduleEntitySave();
                      }}
                      className="w-full h-9 rounded-md border border-border bg-background px-2 text-sm"
                      placeholder="Ped config id"
                    />
                  </div>
                )}

                {entityDraft.type === "society" && (
                  <div className="space-y-2">
                    {!creatingEntity && (
                      <>
                        <ReadOnlyTransform
                          label="Position"
                          coords={entityDraft.society.coords}
                          heading={entityDraft.society.heading}
                        />
                        <Button
                          size="sm"
                          variant="secondary"
                          onClick={() => editEntityTransform("main")}
                          disabled={busyAction}
                        >
                          Move Position (Gizmo)
                        </Button>
                      </>
                    )}
                    <div className="text-xs text-muted-foreground">
                      Society interaction point for deposit/withdraw. Uses club primary job as society name.
                    </div>
                  </div>
                )}

                {entityDraft.type === "club_entry" && (
                  <div className="space-y-2">
                    {!creatingEntity && (
                      <>
                        <ReadOnlyTransform
                          label="Bouncer Position"
                          coords={entityDraft.clubEntry.bouncerCoords}
                          heading={entityDraft.clubEntry.bouncerHeading}
                        />
                        <Button
                          size="sm"
                          variant="secondary"
                          onClick={() => editEntityTransform("bouncer")}
                          disabled={busyAction}
                        >
                          Move Bouncer (Gizmo)
                        </Button>
                        <ReadOnlyTransform
                          label="Eject Position"
                          coords={entityDraft.clubEntry.ejectCoords}
                          heading={entityDraft.clubEntry.ejectHeading}
                        />
                        <Button
                          size="sm"
                          variant="secondary"
                          onClick={() => editEntityTransform("eject")}
                          disabled={busyAction}
                        >
                          Move Eject (Gizmo)
                        </Button>
                      </>
                    )}
                    <input
                      type="text"
                      value={entityDraft.clubEntry.ped}
                      onChange={(e) => {
                        setEntityDraft((prev) => ({
                          ...prev,
                          clubEntry: { ...prev.clubEntry, ped: e.target.value },
                        }));
                        scheduleEntitySave();
                      }}
                      className="w-full h-9 rounded-md border border-border bg-background px-2 text-sm"
                      placeholder="Bouncer ped config id"
                    />
                  </div>
                )}

                <div className="flex gap-2">
                  {creatingEntity && (
                    <Button size="sm" onClick={createEntity} disabled={busyAction}>
                      Create Entity
                    </Button>
                  )}
                  {!creatingEntity && (
                    <Button size="sm" variant="destructive" onClick={deleteEntity} disabled={busyAction}>
                      Delete Entity
                    </Button>
                  )}
                </div>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
