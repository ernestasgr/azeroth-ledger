# Azeroth Ledger

Azeroth Ledger records the items a player encounters in World of Warcraft: Forever, preserving discoveries separately from repeated acquisitions.

## Language

**Collection**:
The discovery view containing one entry per distinct item or gear variant, rather than one entry per acquisition.
_Avoid_: Journal, inventory

**Account collection**:
The collection shared across all characters and realms recorded in this WoW account's local addon data. Character and realm filters narrow this shared collection.

**Discovery**:
The first recorded encounter with an item or gear variant in the account collection. Each entry has one account discovery, even when other characters later encounter it; an initial observation establishes a discovery without establishing an acquisition date or producing a new-discovery toast.

**Character first-seen date**:
The first date a particular character encountered an account collection entry. It is separate from the account discovery and does not create another account discovery.

**Observation date**:
The date an item was seen by the ledger, which need not be its acquisition date. First and latest observation dates are tracked separately from evidenced acquisitions.

**Acquisition date**:
The date an evidenced acquisition occurred. First and latest acquisition dates remain unknown for an entry known only through observation.

**Journal**:
The chronological record of acquisitions and their quantities, plus distinctly labelled internal transfers and vendor reversals. Its retained history is limited independently of permanent collection totals; transfers do not contribute to acquired quantity or discovery count.
_Avoid_: Collection

**Acquisition**:
An evidenced occasion on which an item enters the account's recorded holdings from outside those holdings. Internal transfers are not acquisitions; obtaining an item again after disposal is, unless the transaction is a vendor buyback.
_Avoid_: Bag change

**Acquired quantity**:
The cumulative number of evidenced units recorded entering the account's holdings from outside, adjusted by explicit vendor reversals. Initial observed stock and internal transfers do not increase it; earlier unrecorded acquisitions remain unknown.

**Observed stock**:
The quantity found during an initial inventory or bank scan without evidence of an acquisition. It establishes holdings and discovery, but not an acquired quantity or acquisition date.

**Found once**:
A filter for collection entries with exactly one evidenced acquired unit across the account and no earlier observed stock. Entries known only through observation are excluded because their acquired quantity is unknown.

**Internal transfer**:
A known movement of an item between the account's own characters or their storage. It appears as a distinct Journal event and changes character holdings history without increasing account acquired quantity or creating another account discovery.

**Vendor reversal**:
A refund that cancels a completed purchase's contribution to acquired quantity, or a buyback that restores a sold item without a new acquired unit. Both remain visible in the Journal.

**Acquisition method**:
The means by which an item was obtained, such as loot, quest reward, crafting, vendor purchase, trade, or mail. A method may be unknown when the evidence does not establish it.
_Avoid_: Provenance level

**Provenance level**:
The strength and kind of evidence supporting an item record: Looted, Obtained, or Observed. It is distinct from the acquisition method; a Collection entry shows both its initial level and the strongest later evidence without rewriting earlier records.

**Looted**:
An acquisition supported by a confirmed personal loot event.

**Obtained**:
An item detected entering a character's holdings through another method, without confirmed personal loot evidence.

**Observed**:
An item found in an initial bag or bank scan without evidence establishing how or when it was acquired.
_Avoid_: Looted

**Acquisition evidence**:
The evidence attached to a particular acquisition, separate from an earlier observation of the same collection entry. A later Looted acquisition does not rewrite the original Observed discovery.

**Gear variant**:
A distinct intrinsic form of an item, including its random suffix or bonus data where present. Enchants, gems, durability, and ownership do not define identity; the full observed item link remains part of the record.

**Last-known holdings**:
The items a character was recorded as holding at the latest relevant observation, accompanied by its date and storage scope. A partial scan can establish presence, while absence requires complete relevant scans; neither guarantees live ownership for an offline character.

**Unknown ownership**:
An ownership state used when incomplete or inaccessible relevant storage prevents a last-known presence or absence finding. An offline character's live ownership is unknown even when a dated complete scan establishes last-known absence.

**Zone or dungeon collection**:
A grouping of the account's recorded discoveries by evidenced acquisition location or source dungeon. An initial bag or bank observation has unknown origin and does not establish membership; the grouping is not a checklist of every possible drop.

**Historical ownership**:
Evidence that a character previously held an item, independent of whether they still hold it.

**Historical-only**:
A filter for items with historical ownership and zero last-known holdings across the selected characters' complete relevant scans. It reports absence as of those scan dates; incomplete storage makes the result Unknown.

**Source**:
The mob, boss, or container linked to an acquisition by item-specific evidence when detectable.
_Avoid_: Acquisition method
