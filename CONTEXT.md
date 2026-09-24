# Azeroth Ledger

Azeroth Ledger records the items a player encounters in World of Warcraft: Forever, preserving discoveries separately from repeated acquisitions.

## Language

**Collection**:
The discovery view containing one entry per distinct item or gear variant, rather than one entry per acquisition.
_Avoid_: Journal, inventory

**Account collection**:
The collection shared across all characters and realms recorded in this WoW account's local addon data. Character and realm filters narrow this shared collection.

**Discovery**:
The first recorded encounter with an item or gear variant in the account collection. An initial observation counts as a discovery without establishing an acquisition date or producing a new-discovery toast.

**Observation date**:
The date an item was first seen by the ledger, which need not be its acquisition date.

**Acquisition date**:
The date an evidenced acquisition occurred. It remains unknown for an item known only through an initial observation.

**Journal**:
The chronological record of acquisitions and their quantities. Its retained history is limited independently of permanent collection totals.
_Avoid_: Collection

**Acquisition**:
An occasion on which a character obtains an item from a source outside their existing holdings. Moving an item between that character's bags and bank is not an acquisition.
_Avoid_: Bag change

**Acquisition method**:
The means by which an item was obtained, such as loot, quest reward, crafting, vendor purchase, trade, or mail. A method may be unknown when the evidence does not establish it.
_Avoid_: Provenance level

**Provenance level**:
The strength and kind of evidence supporting an item record: Looted, Obtained, or Observed. It is distinct from the acquisition method.

**Looted**:
An acquisition supported by a confirmed personal loot event.

**Obtained**:
An item detected entering a character's holdings through another method, without confirmed personal loot evidence.

**Observed**:
An item found in an initial bag or bank scan without evidence establishing how or when it was acquired.
_Avoid_: Looted

**Gear variant**:
A distinct intrinsic form of an item, including its random suffix or bonus data where present. Enchanting or socketing alone does not create a new collection entry; the full observed item link remains part of the record.

**Last-known holdings**:
The items a character was recorded as holding at their latest relevant observation, accompanied by the observation time. This is not a guarantee that inaccessible storage or an offline character still holds them.

**Unknown ownership**:
An ownership state used when available observations cannot establish whether an item is still held or absent.

**Zone or dungeon collection**:
A grouping of the account's recorded discoveries associated with a zone or dungeon. It is not a checklist of every possible drop.

**Historical ownership**:
Evidence that a character previously held an item, independent of whether they still hold it.

**Source**:
The mob, boss, or container associated with an acquisition when detectable.
_Avoid_: Acquisition method
