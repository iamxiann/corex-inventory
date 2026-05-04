const CONFIG = {
    cellSize: 64,
    gapSize: 6,
    gridCols: 8,
    gridRows: 10,
    weightSegments: 20
};

let inventoryData = null;
let groundItems = [];
let itemsData = {};
let selectedItem = null;
let isDragging = false;
let draggedEl = null;
let draggedItem = null;
let draggedItemDef = null;
let dragSource = null;
let dragOffsetX = 0;
let dragOffsetY = 0;
let dragPreview = null;
let isActionPending = false;

// Persisted UI state (so sort/search survive inventory updates)
window.__invSearchQuery = window.__invSearchQuery || '';
window.__invSortMode = window.__invSortMode || 'default';

function nuiRequestId() {
    if (window.crypto && typeof window.crypto.randomUUID === 'function') {
        return window.crypto.randomUUID();
    }
    return 'r_' + Date.now() + '_' + Math.random().toString(36).slice(2);
}

const container = document.getElementById('inventory-container');
const vehicleShopContainer = document.getElementById('vehicle-shop-container');
const playerGrid = document.getElementById('player-grid');
const dropGrid = document.getElementById('drop-grid');
const contextMenu = document.getElementById('context-menu');
const weightSegmentsContainer = document.getElementById('weight-segments');
const itemInfoTitle = document.getElementById('item-info-title');
const itemInfoRarity = document.getElementById('item-info-rarity');
const itemInfoMeta = document.getElementById('item-info-meta');
const itemInfoDesc = document.getElementById('item-info-desc');

function resolveItemDefinition(itemName) {
    if (!itemName) {
        return { name: '', size: { w: 1, h: 1 }, label: 'Unknown Item', weight: 0 };
    }

    const rawName = String(itemName);
    const lowerName = rawName.toLowerCase();
    const upperName = rawName.toUpperCase();

    return itemsData[rawName]
        || itemsData[lowerName]
        || itemsData[upperName]
        || Object.values(itemsData).find((def) => {
            const defName = String(def?.name || '').toLowerCase();
            const defLabel = String(def?.label || '').toLowerCase();
            return defName === lowerName || defLabel === lowerName;
        })
        || { name: rawName, size: { w: 1, h: 1 }, label: rawName, weight: 0 };
}

function normalizedItemName(itemOrName) {
    const rawName = typeof itemOrName === 'string' ? itemOrName : itemOrName?.name;
    return String(rawName || '').trim().toLowerCase();
}

function canItemsMerge(sourceItem, targetItem) {
    if (!sourceItem || !targetItem || sourceItem.slot === targetItem.slot) {
        return false;
    }

    // Client-side only checks name match.
    // Server remains the source of truth (stackable/maxStack/weight rules).
    return normalizedItemName(sourceItem) === normalizedItemName(targetItem);
}

function formatItemDetails(item, itemDef) {
    const details = [];
    const stackLabel = itemDef.stackable ? `Stack ${item.count || 1}/${itemDef.maxStack || 'inf'}` : 'Non-stackable';
    details.push(stackLabel);

    if (itemDef.weight != null) {
        details.push(`Weight ${(itemDef.weight * (item.count || 1)).toFixed(2)}kg`);
    }

    if (itemDef.size) {
        details.push(`Size ${(itemDef.size.w || 1)}x${(itemDef.size.h || 1)}`);
    }

    if (itemDef.category) {
        details.push(String(itemDef.category));
    }

    const meta = item?.metadata || {};
    if (meta.ammo != null) details.push(`Ammo ${meta.ammo}`);
    if (meta.durability != null) details.push(`Durability ${Math.round(Number(meta.durability) || 0)}%`);
    if (meta.serial) details.push(`Serial ${meta.serial}`);

    return details.join(' â€¢ ');
}

function updateItemInfo(item) {
    if (!item) {
        itemInfoTitle.textContent = 'Item Info';
        itemInfoRarity.textContent = 'Select an item';
        itemInfoRarity.className = 'item-info-rarity';
        itemInfoMeta.textContent = 'Hover or click an item to see details.';
        itemInfoDesc.textContent = 'Item description and metadata will appear here.';
        return;
    }

    const itemDef = resolveItemDefinition(item.name);
    const rarity = String(itemDef.rarity || item.rarity || 'common');
    const meta = item.metadata || {};
    const description = meta.description
        || itemDef.description
        || itemDef.survival && 'Consumable survival item.'
        || (itemDef.usable ? 'Usable inventory item.' : 'Stored inventory item.');

    itemInfoTitle.textContent = itemDef.label || item.name;
    itemInfoRarity.textContent = rarity.toUpperCase();
    itemInfoRarity.className = `item-info-rarity rarity-text-${rarity}`;
    itemInfoMeta.textContent = formatItemDetails(item, itemDef);
    itemInfoDesc.textContent = description;
}

function initializeUI() {
    renderSlots(playerGrid, CONFIG.gridCols, CONFIG.gridRows);
    renderSlots(dropGrid, CONFIG.gridCols, CONFIG.gridRows);
    renderWeightSegments();
    createDragPreview();
}

function renderSlots(grid, cols, rows) {
    grid.innerHTML = '';
    grid.style.gridTemplateColumns = `repeat(${cols}, ${CONFIG.cellSize}px)`;

    const frag = document.createDocumentFragment();
    for (let row = 1; row <= rows; row++) {
        for (let col = 1; col <= cols; col++) {
            const slot = document.createElement('div');
            slot.className = 'slot';
            slot.dataset.col = col;
            slot.dataset.row = row;
            frag.appendChild(slot);
        }
    }
    grid.appendChild(frag);
}

function renderWeightSegments() {
    weightSegmentsContainer.innerHTML = '';
    const frag = document.createDocumentFragment();
    for (let i = 0; i < CONFIG.weightSegments; i++) {
        const segment = document.createElement('div');
        segment.className = 'weight-segment';
        frag.appendChild(segment);
    }
    weightSegmentsContainer.appendChild(frag);
}

function createDragPreview() {
    if (dragPreview) dragPreview.remove();
    dragPreview = document.createElement('div');
    dragPreview.className = 'drag-preview hidden';
    document.body.appendChild(dragPreview);
}

function updateWeightBar(current, max) {
    const segments = weightSegmentsContainer.querySelectorAll('.weight-segment');
    const percentage = Math.min((current / max) * 100, 100);
    const filledCount = Math.round((percentage / 100) * CONFIG.weightSegments);

    segments.forEach((segment, index) => {
        segment.classList.remove('filled', 'warning', 'danger');
        if (index < filledCount) {
            if (percentage >= 90) {
                segment.classList.add('danger');
            } else if (percentage >= 70) {
                segment.classList.add('warning');
            } else {
                segment.classList.add('filled');
            }
        }
    });

    document.getElementById('current-weight').textContent = Math.round(current);
    document.getElementById('max-weight').textContent = Math.round(max);
}

function checkCollision(x, y, w, h, items, excludeSlot) {
    if (x < 1 || y < 1 || x + w - 1 > CONFIG.gridCols || y + h - 1 > CONFIG.gridRows) {
        return true;
    }

    for (const item of items) {
        if (item.slot === excludeSlot) continue;

        const itemDef = itemsData[item.name] || { size: { w: 1, h: 1 } };
        const itemW = itemDef.size?.w || 1;
        const itemH = itemDef.size?.h || 1;

        const itemRight = item.x + itemW - 1;
        const itemBottom = item.y + itemH - 1;
        const newRight = x + w - 1;
        const newBottom = y + h - 1;

        const overlapsX = !(newRight < item.x || x > itemRight);
        const overlapsY = !(newBottom < item.y || y > itemBottom);

        if (overlapsX && overlapsY) {
            return true;
        }
    }

    return false;
}

function applySearchFallback(query) {
    const q = String(query || '').trim().toLowerCase();
    window.__invSearchQuery = q;
    const grid = document.getElementById('player-grid');
    if (!grid) return;

    const items = Array.from(grid.querySelectorAll('.item:not(.dragging)'));
    items.forEach((el) => {
        const haystack = [
            el.dataset.name || '',
            el.dataset.label || '',
            el.dataset.description || '',
            el.getAttribute('title') || '',
        ].join(' ').toLowerCase();

        const match = !q || haystack.includes(q);
        el.style.display = match ? '' : 'none';
        el.style.pointerEvents = match ? 'auto' : 'none';
        el.style.opacity = match ? '' : '0';
    });
}

function clearSortLocks() {
    const grid = document.getElementById('player-grid');
    if (!grid) return;
    grid.querySelectorAll('.item[data-sort-locked="true"]').forEach((el) => {
        delete el.dataset.sortLocked;
    });
}

function markLockedSortItemsFromHotkeys() {
    const grid = document.getElementById('player-grid');
    if (!grid) return;
    clearSortLocks();

    const mapping = window.hotkeyMapping || [];
    for (let slotNum = 1; slotNum <= 6; slotNum++) {
        const m = mapping[slotNum];
        if (!m || m.type !== 'item' || !m.item) continue;
        const slotStr = String(m.item.slot);
        const itemEl =
            grid.querySelector(`.item[data-slot="${CSS.escape(slotStr)}"]`)
            || grid.querySelector(`.item[data-x="${m.col}"][data-y="${m.row}"]`);
        if (itemEl) {
            itemEl.dataset.sortLocked = 'true';
        }
    }
}

function getItemRarityRankFromEl(el) {
    const rank = { common: 0, uncommon: 1, rare: 2, epic: 3, legendary: 4, mythic: 5 };
    for (const key in rank) {
        if (el.classList.contains('rarity-' + key)) return rank[key];
    }
    return 0;
}

function getItemWeightFromEl(el) {
    const w = el.querySelector('.item-weight');
    if (!w) return 0;
    const value = parseFloat(String(w.textContent || '').replace(/[^\d.]/g, ''));
    return Number.isFinite(value) ? value : 0;
}

function getItemLabelFromEl(el) {
    const label = el.dataset.label || el.dataset.name || '';
    return String(label).toLowerCase();
}

function restoreGridPositionsFallback() {
    const grid = document.getElementById('player-grid');
    if (!grid) return;
    const step = CONFIG.cellSize + CONFIG.gapSize;
    grid.querySelectorAll('.item').forEach((el) => {
        const x = parseInt(el.dataset.x, 10) || 1;
        const y = parseInt(el.dataset.y, 10) || 1;
        el.style.left = ((x - 1) * step) + 'px';
        el.style.top = ((y - 1) * step) + 'px';
        if (el.style.display === 'none') el.style.display = '';
        el.classList.remove('sort-moved');
    });
}

function packDomItemsFallback(sortedEls) {
    const grid = document.getElementById('player-grid');
    if (!grid) return;
    const step = CONFIG.cellSize + CONFIG.gapSize;
    const occ = new Set();

    const fits = (c, r, w, h) => {
        if (c + w - 1 > CONFIG.gridCols || r + h - 1 > CONFIG.gridRows) return false;
        for (let dr = 0; dr < h; dr++) {
            for (let dc = 0; dc < w; dc++) {
                if (occ.has((c + dc) + ',' + (r + dr))) return false;
            }
        }
        return true;
    };

    const occupy = (c, r, w, h) => {
        for (let dr = 0; dr < h; dr++) {
            for (let dc = 0; dc < w; dc++) {
                occ.add((c + dc) + ',' + (r + dr));
            }
        }
    };

    // Pre-occupy locked items so sorted items never overlap them
    const lockedEls = Array.from(grid.querySelectorAll('.item[data-sort-locked="true"]'));
    lockedEls.forEach((el) => {
        const x = parseInt(el.dataset.x, 10) || 1;
        const y = parseInt(el.dataset.y, 10) || 1;
        const w = Math.max(1, Math.round((parseInt(el.style.width, 10) + CONFIG.gapSize) / step));
        const h = Math.max(1, Math.round((parseInt(el.style.height, 10) + CONFIG.gapSize) / step));
        occupy(x, y, w, h);
    });

    sortedEls.forEach((el) => {
        const w = Math.max(1, Math.round((parseInt(el.style.width, 10) + CONFIG.gapSize) / step));
        const h = Math.max(1, Math.round((parseInt(el.style.height, 10) + CONFIG.gapSize) / step));

        let placed = false;
        outer:
        for (let row = 1; row <= CONFIG.gridRows; row++) {
            for (let col = 1; col <= CONFIG.gridCols; col++) {
                if (fits(col, row, w, h)) {
                    occupy(col, row, w, h);
                    el.style.left = ((col - 1) * step) + 'px';
                    el.style.top = ((row - 1) * step) + 'px';
                    el.dataset.x = String(col);
                    el.dataset.y = String(row);
                    el.classList.add('sort-moved');
                    placed = true;
                    break outer;
                }
            }
        }
        if (!placed) el.style.display = 'none';
    });
}

function persistCompactLayoutToServer() {
    const grid = document.getElementById('player-grid');
    if (!grid) return;

    // Only persist non-locked items; hotbar 1-6 are locked.
    const els = Array.from(grid.querySelectorAll('.item'))
        .filter((el) => el.dataset.sortLocked !== 'true');

    const positions = els.map((el) => {
        const slotId = el.dataset.slot;
        const x = parseInt(el.dataset.x, 10) || 1;
        const y = parseInt(el.dataset.y, 10) || 1;
        return { slotId, x, y };
    }).filter((p) => p.slotId != null);

    if (!positions.length) return;

    fetch(`https://${GetParentResourceName()}/compactInventory`, {
        method: 'POST',
        body: JSON.stringify({ positions })
    }).catch(() => {});
}

function applySortFallback(mode) {
    window.__invSortMode = mode || 'default';
    const grid = document.getElementById('player-grid');
    if (!grid) return;

    if (mode === 'default') {
        // "Grip" = compact/rapihin layout (pack items into earliest free slots).
        // Hotbar/quickslot 1-6 items are locked and must not move.
        markLockedSortItemsFromHotkeys();

        const els = Array.from(grid.querySelectorAll('.item:not(.dragging)'))
            .filter((el) => el.dataset.sortLocked !== 'true');

        packDomItemsFallback(els);
        return;
    }

    markLockedSortItemsFromHotkeys();

    const els = Array.from(grid.querySelectorAll('.item:not(.dragging)'))
        .filter((el) => el.style.display !== 'none')
        .filter((el) => el.dataset.sortLocked !== 'true');
    els.sort((a, b) => {
        switch (mode) {
            case 'name':
                return getItemLabelFromEl(a).localeCompare(getItemLabelFromEl(b));
            case 'weight+':
                return getItemWeightFromEl(a) - getItemWeightFromEl(b);
            case 'weight-':
                return getItemWeightFromEl(b) - getItemWeightFromEl(a);
            case 'rarity':
                return getItemRarityRankFromEl(b) - getItemRarityRankFromEl(a);
            default:
                return 0;
        }
    });

    packDomItemsFallback(els);
}

function wireSearchFallback() {
    const input = document.getElementById('inv-search-input');
    const clearBtn = document.getElementById('inv-search-clear');
    if (!input || !clearBtn) return;

    // Avoid double-wiring if inventory opens multiple times
    if (wireSearchFallback._wired) return;
    wireSearchFallback._wired = true;

    input.addEventListener('input', () => {
        const q = input.value || '';
        window.__invSearchQuery = String(q).trim().toLowerCase();
        clearBtn.classList.toggle('hidden', !String(q).trim());

        if (typeof window.applyInventoryFilter === 'function') {
            window.applyInventoryFilter();
        } else {
            applySearchFallback(q);
        }

        // If sort mode is active, keep layout sorted after filtering
        const mode = window.__invSortMode || 'default';
        if (mode !== 'default') {
            requestAnimationFrame(() => applySortFallback(mode));
        }
    });

    clearBtn.addEventListener('click', (e) => {
        e.preventDefault();
        e.stopPropagation();
        input.value = '';
        clearBtn.classList.add('hidden');
        if (typeof window.resetInventoryFilter === 'function') {
            window.resetInventoryFilter();
        } else {
            applySearchFallback('');
            renderItems();
        }
    });
}

function wireSortFallback() {
    const buttons = Array.from(document.querySelectorAll('.inv-sort-btn'));
    if (!buttons.length) return;
    if (wireSortFallback._wired) return;
    wireSortFallback._wired = true;

    buttons.forEach((btn) => {
        // Capture phase + stopImmediatePropagation so other scripts can't "fight" this handler.
        btn.addEventListener('click', (e) => {
            // Let external inventory-filter.js handle it if present, but always run fallback too
            // so "sort not working" cases still work.
            e.preventDefault();
            e.stopPropagation();
            if (typeof e.stopImmediatePropagation === 'function') e.stopImmediatePropagation();

            const mode = btn.dataset.sort || 'default';
            buttons.forEach((b) => b.classList.remove('active'));
            btn.classList.add('active');

            applySortFallback(mode);
            if (mode === 'default') {
                // Persist compact layout to server.
                // Delay one frame to ensure dataset x/y updated by pack.
                requestAnimationFrame(persistCompactLayoutToServer);
            }
        }, true);
    });
}

document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') {
        e.preventDefault();
        e.stopPropagation();

        if (isDragging) {
            cancelDrag();
        } else if (!container.classList.contains('hidden') || (vehicleShopContainer && !vehicleShopContainer.classList.contains('hidden'))) {
            closeInventory();
        }
    }
});

document.addEventListener('click', (e) => {
    if (!contextMenu.contains(e.target) && !playersSubmenu.contains(e.target)) {
        hideContextMenu();
    }
});

function openInventory(data) {
    inventoryData = data;
    itemsData = data.itemsData || {};

    // Store items globally for hotbar (same as updateInventory)
    if (data && data.items) {
        window.latestInventoryItems = data.items;
    }

    if (data.grid) {
        CONFIG.gridCols = data.grid.w || 8;
        CONFIG.gridRows = data.grid.h || 10;
    }

    if (data.groundItems) {
        groundItems = data.groundItems;
    }

    const dropTitle = document.getElementById('drop-title');
    const dropIcon = document.getElementById('drop-icon');
    const dropHint = document.getElementById('drop-hint');
    const shopMoney = document.getElementById('shop-money');
    const playerMoneySpan = document.getElementById('player-money');

    if (data.isShop) {
        dropTitle.textContent = data.shopName || 'Shop';
        dropIcon.className = 'fa-solid fa-store hex-inner-icon';
        dropHint.classList.add('hidden');
        shopMoney.classList.remove('hidden');
        playerMoneySpan.textContent = '$' + (data.playerMoney || 0);
        dropGrid.classList.add('is-shop');
    } else if (data.isStash) {
        dropTitle.textContent = data.stashName || 'Storage';
        dropIcon.className = 'fa-solid fa-box-archive hex-inner-icon';
        dropHint.classList.add('hidden');
        shopMoney.classList.add('hidden');
        dropGrid.classList.remove('is-shop');
    } else {
        dropTitle.textContent = 'Ground';
        dropIcon.className = 'fa-solid fa-arrow-down hex-inner-icon';
        dropHint.classList.remove('hidden');
        shopMoney.classList.add('hidden');
        dropGrid.classList.remove('is-shop');
    }

    initializeUI();
    updateWeightBar(data.weight || 0, data.maxWeight || 200);
    renderItems();
    renderGroundItems();
    updateItemInfo(null);
    wireSearchFallback();
    wireSortFallback();
    container.classList.remove('hidden');
}

function updateInventory(data) {
    inventoryData = data;
    if (data.itemsData) itemsData = data.itemsData;
    if (data.groundItems) groundItems = data.groundItems;

    // Store items globally so hotbar can update even when inventory is closed
    if (data && data.items) {
        window.latestInventoryItems = data.items;
        assignHotkeysToSlots(data.items); // Always update hotbar
    }

    updateWeightBar(data.weight || 0, data.maxWeight || 200);
    renderItems();
    renderGroundItems();
    // [FIX-SORT-3] Re-apply filter/sort after update
    if (typeof window.applyInventoryFilter === 'function') {
        requestAnimationFrame(window.applyInventoryFilter);
    }
}

function updateGroundItems(items) {
    groundItems = items;
    renderGroundItems();
}

function closeInventory() {
    if (container.classList.contains('hidden')) return;

    if (isContainerMode) {
        const cId = containerData?.containerId;
        closeLootContainer();
        fetch(`https://${GetParentResourceName()}/closeLootContainer`, {
            method: 'POST',
            body: JSON.stringify({ containerId: cId })
        }).catch(() => {});
    }

    fetch(`https://${GetParentResourceName()}/close`, {
        method: 'POST',
        body: JSON.stringify({})
    }).catch(() => {});
}

function cancelDrag() {
    if (draggedEl) {
        draggedEl.classList.remove('dragging');
        draggedEl.style.position = '';
        draggedEl.style.zIndex = '';
        draggedEl.style.left = '';
        draggedEl.style.top = '';
    }

    isDragging = false;
    draggedEl = null;
    draggedItem = null;
    draggedItemDef = null;
    dragSource = null;
    hideDragPreview();

    document.removeEventListener('mousemove', handleDragMove);
    document.removeEventListener('mouseup', handleDragEnd);

    renderItems();
    renderGroundItems();
}

function renderItems() {
    playerGrid.querySelectorAll('.item').forEach(item => item.remove());
    playerGrid.querySelectorAll('.quickslot-number').forEach(num => num.remove());

    if (!inventoryData || !inventoryData.items) {
        assignHotkeysToSlots([]);
        return;
    }

    const frag = document.createDocumentFragment();
    inventoryData.items.forEach(item => {
        frag.appendChild(createItemElement(item, 'player'));
    });
    playerGrid.appendChild(frag);

    assignHotkeysToSlots(inventoryData.items);

    // Re-apply search/sort after fresh render (prevents "berantakan" after any update)
    requestAnimationFrame(() => {
        const q = window.__invSearchQuery || '';
        if (q) applySearchFallback(q);

        const mode = window.__invSortMode || 'default';
        if (mode && mode !== 'default') {
            applySortFallback(mode);
        }
    });
}

function assignHotkeysToSlots(items) {
    const coveredSlots = new Set();
    const anchorSlots = new Map();

    items.forEach(item => {
        const itemDef = itemsData[item.name] || { size: { w: 1, h: 1 } };
        const w = itemDef.size?.w || 1;
        const h = itemDef.size?.h || 1;
        const anchorKey = `${item.x},${item.y}`;
        anchorSlots.set(anchorKey, item);

        for (let row = item.y; row < item.y + h; row++) {
            for (let col = item.x; col < item.x + w; col++) {
                const key = `${col},${row}`;
                if (key !== anchorKey) {
                    coveredSlots.add(key);
                }
            }
        }
    });

    let currentHotkey = 1;
    const hotkeyMapping = [];

    for (let row = 1; row <= CONFIG.gridRows && currentHotkey <= 6; row++) {
        for (let col = 1; col <= CONFIG.gridCols && currentHotkey <= 6; col++) {
            const key = `${col},${row}`;

            if (coveredSlots.has(key)) {
                continue;
            }

            const slot = playerGrid.querySelector(`.slot[data-col="${col}"][data-row="${row}"]`);
            if (!slot) continue;

            if (anchorSlots.has(key)) {
                const item = anchorSlots.get(key);
                const itemEl = playerGrid.querySelector(`.item[data-x="${col}"][data-y="${row}"]`);
                if (itemEl) {
                    const numBadge = document.createElement('span');
                    numBadge.className = 'quickslot-number';
                    numBadge.textContent = currentHotkey;
                    itemEl.appendChild(numBadge);
                }
                hotkeyMapping[currentHotkey] = { col, row, type: 'item', item };
                currentHotkey++;
            } else {
                const numBadge = document.createElement('span');
                numBadge.className = 'quickslot-number';
                numBadge.textContent = currentHotkey;
                slot.appendChild(numBadge);
                hotkeyMapping[currentHotkey] = { col, row, type: 'empty' };
                currentHotkey++;
            }
        }
    }

    window.hotkeyMapping = hotkeyMapping;
    syncHotbarWithInventory(hotkeyMapping);

    // Keep sort-locks up to date after mapping changes
    markLockedSortItemsFromHotkeys();
}

function syncHotbarWithInventory(hotkeyMapping) {
    const hotbarSlots = document.querySelectorAll('.hotbar-slot');

    hotbarSlots.forEach(slot => {
        const slotNum = parseInt(slot.dataset.slot);
        const mapping = hotkeyMapping[slotNum];

        // Clear current slot
        const existingImg = slot.querySelector('.hotbar-item-image');
        const existingCount = slot.querySelector('.hotbar-item-count');
        const existingRarity = slot.querySelector('.hotbar-rarity-bar'); // if any from previous generic render

        if (existingImg) existingImg.remove();
        if (existingCount) existingCount.remove();
        if (existingRarity) existingRarity.remove();

        slot.className = 'hotbar-slot';
        delete slot.dataset.rarity;

        if (mapping && mapping.type === 'item' && mapping.item) {
            const item = mapping.item;

            let itemDef = itemsData[item.name];
            if (!itemDef) itemDef = itemsData[item.name.toLowerCase()];
            if (!itemDef) itemDef = itemsData[item.name.toUpperCase()];
            if (!itemDef) {
                itemDef = Object.values(itemsData).find(d => d.label === item.name || d.name === item.name);
            }
            if (!itemDef) itemDef = {};

            const rarity = itemDef.rarity || item.rarity || 'common';

            slot.classList.add('has-item');
            slot.dataset.rarity = rarity;

            const img = document.createElement('img');
            img.className = 'hotbar-item-image';
            img.src = `images/${itemDef.image || item.name.toLowerCase() + '.png'}`;
            img.alt = itemDef.label || item.name;
            img.onerror = function () {
                this.src = 'images/default.png';
            };

            const count = document.createElement('span');
            count.className = 'hotbar-item-count';
            if (item.count >= 1) count.textContent = item.count;

            slot.appendChild(img);
            slot.appendChild(count);
        }
    });
}

function renderGroundItems() {
    dropGrid.querySelectorAll('.item').forEach(item => item.remove());
    dropGrid.querySelectorAll('.shop-card').forEach(item => item.remove());

    if (inventoryData && inventoryData.isShop) {
        const frag = document.createDocumentFragment();
        groundItems.forEach((item) => {
            frag.appendChild(createShopCard(item));
        });
        dropGrid.appendChild(frag);
        return;
    }

    const frag = document.createDocumentFragment();
    groundItems.forEach((item) => {
        frag.appendChild(createItemElement(item, 'ground'));
    });
    dropGrid.appendChild(frag);
}

function escapeHtml(value) {
    return String(value ?? '').replace(/[&<>"']/g, (char) => ({
        '&': '&amp;',
        '<': '&lt;',
        '>': '&gt;',
        '"': '&quot;',
        "'": '&#39;'
    }[char]));
}

function purchaseShopItem(item, amount = 1) {
    if (!inventoryData || !inventoryData.isShop || !item || !item.name) return;
    if (isActionPending) return;

    isActionPending = true;
    fetch(`https://${GetParentResourceName()}/purchaseShopItem`, {
        method: 'POST',
        body: JSON.stringify({
            itemName: item.name,
            amount: amount
        })
    }).catch(() => {}).finally(() => {
        setTimeout(() => {
            isActionPending = false;
        }, 450);
    });
}

function createShopCard(item) {
    let itemDef = itemsData[item.name];
    if (!itemDef) itemDef = itemsData[item.name.toLowerCase()];
    if (!itemDef) itemDef = itemsData[item.name.toUpperCase()];
    if (!itemDef) {
        itemDef = Object.values(itemsData).find(d => d.label === item.name || d.name === item.name) || { label: item.name, description: 'No description available.', size: {w:1, h:1} };
    }
    
    const rarity = itemDef.rarity || 'common';
    const rarityLabel = rarity.charAt(0).toUpperCase() + rarity.slice(1);
    
    const el = document.createElement('div');
    el.className = `shop-card rarity-border-${rarity}`;
    
    const cat = itemDef.category || 'Item';
    const itemLabel = itemDef.label || item.name;
    const itemDesc = itemDef.description ? itemDef.description : 'A valuable survival item.';
    const imageName = itemDef.image || item.name.toLowerCase() + '.png';
    
    el.innerHTML = `
        <div class="shop-card-content">
            <div class="shop-card-image rarity-bg-${rarity}">
                <img src="images/${escapeHtml(imageName)}" onerror="this.onerror=null;this.src='images/default.png';" alt="">
            </div>
            <div class="shop-card-info">
                <div class="shop-card-header">
                    <span class="shop-card-name">${escapeHtml(itemLabel)}</span>
                    <span class="shop-card-price">$${item.price || 0}</span>
                </div>
                <div class="shop-card-desc">${escapeHtml(itemDesc)}</div>
                <div class="shop-card-footer">
                    <div class="shop-card-tags">
                        <span class="shop-card-cat">${escapeHtml(cat)}</span>
                        <span class="shop-card-rarity rarity-text-${rarity}">${escapeHtml(rarityLabel)}</span>
                    </div>
                    <button class="shop-buy-btn" type="button">BUY</button>
                </div>
            </div>
        </div>
    `;

    el.dataset.slot = item.slot;
    el.dataset.name = item.name;
    el.dataset.count = item.count || 1;
    el.dataset.source = 'ground';
    el.dataset.isShopItem = 'true';
    el.dataset.price = item.price || 0;
    el.dataset.currency = item.currency || 'cash';

    const buyButton = el.querySelector('.shop-buy-btn');
    if (buyButton) {
        buyButton.addEventListener('click', (e) => {
            e.preventDefault();
            e.stopPropagation();
            purchaseShopItem(item, 1);
        });
    }
    el.addEventListener('dblclick', () => purchaseShopItem(item, 1));
    return el;
}

function createItemElement(item, source, quickslotNum) {
    const itemDef = resolveItemDefinition(item.name);
    const displaySize = item.isShopItem && item.displaySize ? item.displaySize : (itemDef.size || { w: 1, h: 1 });
    const w = displaySize.w || 1;
    const h = displaySize.h || 1;
    const category = itemDef.category || '';
    const isAmmoItem = item.name.toLowerCase().includes('ammo') || (!!itemDef.maxStack && !itemDef.ammoType && !category);
    const itemTypeClass = isAmmoItem ? 'item-type-ammo' : 'item-type-weapon';
    const categoryClass = category ? `item-category-${category}` : '';
    const rarity = itemDef.rarity || 'common';
    const rarityLabel = {
        common: 'COMMON',
        uncommon: 'UNCOMMON',
        rare: 'RARE',
        epic: 'EPIC',
        legendary: 'LEGENDARY',
        mythic: 'MYTHIC'
    }[rarity] || 'COMMON';

    const el = document.createElement('div');
    el.className = `item rarity-${rarity}`;
    if (item.isShopItem) {
        el.classList.add('shop-item');
        el.classList.add(itemTypeClass);
        if (categoryClass) {
            el.classList.add(categoryClass);
        }
        if (w === 1 && h === 1) {
            el.classList.add('shop-item-compact');
        } else if (w >= 2 && h >= 2) {
            el.classList.add('shop-item-large');
        }
    }

    const x = Math.max(1, Math.min(item.x || 1, CONFIG.gridCols));
    const y = Math.max(1, Math.min(item.y || 1, CONFIG.gridRows));

    const left = (x - 1) * (CONFIG.cellSize + CONFIG.gapSize);
    const top = (y - 1) * (CONFIG.cellSize + CONFIG.gapSize);
    const width = w * CONFIG.cellSize + (w - 1) * CONFIG.gapSize;
    const height = h * CONFIG.cellSize + (h - 1) * CONFIG.gapSize;

    el.style.left = left + 'px';
    el.style.top = top + 'px';
    el.style.width = width + 'px';
    el.style.height = height + 'px';

    const totalWeight = ((itemDef.weight || 0) * (item.count || 1)).toFixed(2);
    const quickslotBadge = quickslotNum ? `<span class="quickslot-number">${quickslotNum}</span>` : '';
    const priceTag = item.isShopItem ? `<span class="item-price">$${item.price || 0}</span>` : '';

    el.innerHTML = '';
    const fragment = document.createDocumentFragment();
    if (quickslotBadge) {
        const qs = document.createElement('span');
        qs.className = 'quickslot-number';
        qs.textContent = quickslotNum;
        fragment.appendChild(qs);
    }
    const rarityEl = document.createElement('span');
    rarityEl.className = 'item-rarity';
    rarityEl.textContent = rarityLabel;
    fragment.appendChild(rarityEl);
    const qtyEl = document.createElement('span');
    qtyEl.className = 'item-qty';
    qtyEl.textContent = item.count || 1;
    fragment.appendChild(qtyEl);
    const weightEl = document.createElement('span');
    weightEl.className = 'item-weight';
    weightEl.textContent = totalWeight + 'kg';
    fragment.appendChild(weightEl);
    if (item.isShopItem) {
        const priceEl = document.createElement('span');
        priceEl.className = 'item-price';
        priceEl.textContent = '$' + (item.price || 0);
        fragment.appendChild(priceEl);
    }
    const img = document.createElement('img');
    img.src = 'images/' + (itemDef.image || 'default.png');
    img.alt = itemDef.label || '';
    img.onerror = function() { this.onerror = null; this.src = 'images/default.png'; };
    fragment.appendChild(img);
    const nameEl = document.createElement('span');
    nameEl.className = 'item-name';
    nameEl.textContent = itemDef.label || item.name;
    fragment.appendChild(nameEl);

    // [FIX-META] Render item metadata badges (ammo, durability, serial, etc.)
    const meta = item.metadata || {};
    const metaBadges = [];
    if (meta.ammo !== undefined && meta.ammo !== null) {
        metaBadges.push({ icon: 'fa-circle-dot', value: meta.ammo, cls: 'meta-ammo', title: 'Ammo: ' + meta.ammo });
    }
    if (meta.durability !== undefined && meta.durability !== null) {
        const dur = typeof meta.durability === 'number' ? Math.round(meta.durability) + '%' : meta.durability;
        metaBadges.push({ icon: 'fa-heart', value: dur, cls: 'meta-durability', title: 'Durability: ' + dur });
    }
    if (meta.serial) {
        metaBadges.push({ icon: 'fa-hashtag', value: String(meta.serial).slice(-4), cls: 'meta-serial', title: 'Serial: ' + meta.serial });
    }
    if (metaBadges.length > 0) {
        const metaContainer = document.createElement('div');
        metaContainer.className = 'item-meta-badges';
        metaBadges.forEach(function(badge) {
            const b = document.createElement('span');
            b.className = 'item-meta-badge ' + badge.cls;
            b.title = badge.title;
            b.innerHTML = '<i class="fa-solid ' + badge.icon + '"></i> ' + escapeHtml(String(badge.value));
            metaContainer.appendChild(b);
        });
        fragment.appendChild(metaContainer);
    }

    el.appendChild(fragment);

    el.dataset.slot = item.slot;
    el.dataset.name = item.name;
    el.dataset.label = itemDef.label || item.name;
    el.dataset.description = item.metadata?.description || itemDef.description || '';
    el.dataset.count = item.count || 1;
    el.dataset.source = source;
    el.dataset.x = x;
    el.dataset.y = y;
    el.title = [el.dataset.label, el.dataset.description].filter(Boolean).join(' - ');
    if (item.isShopItem) {
        el.dataset.isShopItem = 'true';
        el.dataset.price = item.price || 0;
        el.dataset.currency = item.currency || 'cash';
    }

    if (source === 'player') {
        el.addEventListener('mouseenter', () => updateItemInfo(item));
        el.addEventListener('click', () => updateItemInfo(item));
    }
    el.addEventListener('contextmenu', (e) => showContextMenu(e, item, source, el));
    el.addEventListener('mousedown', (e) => handleDragStart(e, el, item, source));

    return el;
}

function hideDragPreview() {
    if (!dragPreview) return;
    dragPreview.classList.add('hidden');
    dragPreview.classList.remove('valid', 'invalid', 'drop-zone');
    dragPreview.style.left = '';
    dragPreview.style.top = '';
    dragPreview.style.width = '';
    dragPreview.style.height = '';
}

function getSlotAtPoint(grid, clientX, clientY) {
    if (!grid) return null;
    const node = document.elementFromPoint(clientX, clientY);
    const slot = node && node.closest ? node.closest('.slot') : null;
    if (!slot || !grid.contains(slot)) return null;
    return {
        x: parseInt(slot.dataset.col, 10),
        y: parseInt(slot.dataset.row, 10),
        slot
    };
}

function getPlayerDropTarget(clientX, clientY) {
    if (!playerGrid) return null;
    const node = document.elementFromPoint(clientX, clientY);
    if (!node) return null;

    // If we are over an item, merge/move should still work even though items
    // are absolutely positioned (not inside .slot elements).
    const itemEl = node.closest ? node.closest('.item') : null;
    if (itemEl && playerGrid.contains(itemEl)) {
        const slot = itemEl.dataset.slot;
        const x = parseInt(itemEl.dataset.x, 10);
        const y = parseInt(itemEl.dataset.y, 10);
        if (slot != null && Number.isFinite(x) && Number.isFinite(y)) {
            return { type: 'item', slot, x, y, el: itemEl };
        }
        return { type: 'item', slot, el: itemEl };
    }

    const slotEl = node.closest ? node.closest('.slot') : null;
    if (slotEl && playerGrid.contains(slotEl)) {
        return {
            type: 'slot',
            x: parseInt(slotEl.dataset.col, 10),
            y: parseInt(slotEl.dataset.row, 10),
            el: slotEl
        };
    }

    return null;
}

function getInventoryItemBySlot(slotId) {
    const slotStr = String(slotId);
    return (inventoryData?.items || []).find((it) => String(it.slot) === slotStr) || null;
}

function getItemSize(item) {
    const itemDef = resolveItemDefinition(item.name);
    const size = item.displaySize || itemDef.size || { w: 1, h: 1 };
    return {
        w: size.w || 1,
        h: size.h || 1
    };
}

function showDragPreviewAt(slot, item, valid, dropZone) {
    if (!dragPreview || !slot) return;
    const size = getItemSize(item);
    const rect = slot.slot.getBoundingClientRect();
    const width = size.w * CONFIG.cellSize + (size.w - 1) * CONFIG.gapSize;
    const height = size.h * CONFIG.cellSize + (size.h - 1) * CONFIG.gapSize;

    dragPreview.classList.remove('hidden', 'valid', 'invalid', 'drop-zone');
    dragPreview.classList.add(dropZone ? 'drop-zone' : (valid ? 'valid' : 'invalid'));
    dragPreview.style.left = rect.left + 'px';
    dragPreview.style.top = rect.top + 'px';
    dragPreview.style.width = width + 'px';
    dragPreview.style.height = height + 'px';
}

function handleDragStart(e, el, item, source) {
    if (e.button !== 0 || isActionPending) return;
    if (source === 'container') return;
    if (inventoryData && inventoryData.isShop && source === 'ground') return;

    e.preventDefault();
    e.stopPropagation();
    hideContextMenu();

    isDragging = true;
    draggedEl = el;
    draggedItem = item;
    draggedItemDef = resolveItemDefinition(item.name);
    dragSource = source;

    const rect = el.getBoundingClientRect();
    dragOffsetX = e.clientX - rect.left;
    dragOffsetY = e.clientY - rect.top;

    el.classList.add('dragging');
    el.style.position = 'fixed';
    el.style.left = rect.left + 'px';
    el.style.top = rect.top + 'px';
    el.style.zIndex = '1000';

    document.addEventListener('mousemove', handleDragMove);
    document.addEventListener('mouseup', handleDragEnd);
}

function handleDragMove(e) {
    if (!isDragging || !draggedEl || !draggedItem) return;

    draggedEl.style.left = (e.clientX - dragOffsetX) + 'px';
    draggedEl.style.top = (e.clientY - dragOffsetY) + 'px';

    const playerSlot = getSlotAtPoint(playerGrid, e.clientX, e.clientY);
    const dropSlot = getSlotAtPoint(dropGrid, e.clientX, e.clientY);
    const size = getItemSize(draggedItem);

    if (dragSource === 'player' && playerSlot) {
        const valid = !checkCollision(playerSlot.x, playerSlot.y, size.w, size.h, inventoryData?.items || [], draggedItem.slot);
        showDragPreviewAt(playerSlot, draggedItem, valid, false);
    } else if (dragSource === 'ground' && playerSlot) {
        const valid = !checkCollision(playerSlot.x, playerSlot.y, size.w, size.h, inventoryData?.items || []);
        showDragPreviewAt(playerSlot, draggedItem, valid, false);
    } else if (dragSource === 'player' && dropSlot) {
        const valid = !(inventoryData && inventoryData.isStash)
            || !checkCollision(dropSlot.x, dropSlot.y, size.w, size.h, inventoryData?.groundItems || []);
        showDragPreviewAt(dropSlot, draggedItem, valid, true);
    } else {
        hideDragPreview();
    }
}

// Helper: find item occupying a grid cell (col, row) in a given items array
function getItemAtCell(items, col, row) {
    return items.find(it => {
        const def = resolveItemDefinition(it.name);
        const w = def.size?.w || 1;
        const h = def.size?.h || 1;
        return col >= it.x && col < it.x + w && row >= it.y && row < it.y + h;
    }) || null;
}

function handleDragEnd(e) {
    if (!isDragging || !draggedItem) {
        cancelDrag();
        return;
    }

    const playerTarget = getPlayerDropTarget(e.clientX, e.clientY);
    const dropSlot = getSlotAtPoint(dropGrid, e.clientX, e.clientY);
    const size = getItemSize(draggedItem);

    if (dragSource === 'player' && playerTarget) {
        let targetItem = null;
        if (playerTarget.type === 'item') {
            targetItem = getInventoryItemBySlot(playerTarget.slot) || getItemAtCell(inventoryData?.items || [], playerTarget.x || 1, playerTarget.y || 1);
        } else if (playerTarget.type === 'slot') {
            targetItem = getItemAtCell(inventoryData?.items || [], playerTarget.x, playerTarget.y);
        }

        // Same-name item under cursor â†’ merge
        if (targetItem && canItemsMerge(draggedItem, targetItem)) {
            fetch(`https://${GetParentResourceName()}/mergeItem`, {
                method: 'POST',
                body: JSON.stringify({
                    fromSlot: draggedItem.slot,
                    toSlot: targetItem.slot
                })
            }).catch(() => {});
        } else {
            if (playerTarget.type === 'slot') {
                const valid = !checkCollision(playerTarget.x, playerTarget.y, size.w, size.h, inventoryData?.items || [], draggedItem.slot);
                if (valid) {
                    fetch(`https://${GetParentResourceName()}/moveItem`, {
                        method: 'POST',
                        body: JSON.stringify({
                            slotId: draggedItem.slot,
                            x: playerTarget.x,
                            y: playerTarget.y
                        })
                    }).catch(() => {});
                }
            }
        }
    } else if (dragSource === 'player' && dropSlot) {
        const itemSnap = { ...draggedItem };
        const slotSnap = { ...dropSlot };
        const depositToStash = (amount) => {
            fetch(`https://${GetParentResourceName()}/stashDepositItem`, {
                method: 'POST',
                body: JSON.stringify({
                    stashId: inventoryData?.stashId,
                    slot: itemSnap.slot,
                    count: amount,
                    x: slotSnap.x,
                    y: slotSnap.y
                })
            }).catch(() => {});
        };
        if (inventoryData && inventoryData.isStash) {
            if (checkCollision(slotSnap.x, slotSnap.y, size.w, size.h, inventoryData?.groundItems || [])) {
                cancelDrag();
                return;
            }
            if ((itemSnap.count || 1) <= 1) {
                depositToStash(1);
            } else {
                openDropModal(itemSnap, null, depositToStash);
            }
            cancelDrag();
            return;
        }
        if ((itemSnap.count || 1) <= 1) {
            fetch(`https://${GetParentResourceName()}/dropItem`, {
                method: 'POST',
                body: JSON.stringify({
                    name: itemSnap.name, count: 1,
                    slot: itemSnap.slot, x: slotSnap.x, y: slotSnap.y
                })
            }).catch(() => {});
        } else {
            openDropModal(itemSnap, null, (amount) => {
                fetch(`https://${GetParentResourceName()}/dropItem`, {
                    method: 'POST',
                    body: JSON.stringify({
                        name: itemSnap.name, count: amount,
                        slot: itemSnap.slot, x: slotSnap.x, y: slotSnap.y
                    })
                }).catch(() => {});
            });
        }
    } else if (dragSource === 'ground' && playerTarget) {
        if (inventoryData && inventoryData.isStash) {
            const itemSnap = { ...draggedItem };
            const targetSnap = { ...playerTarget };
            const withdrawFromStash = (amount) => {
                fetch(`https://${GetParentResourceName()}/stashWithdrawItem`, {
                    method: 'POST',
                    body: JSON.stringify({
                        stashId: inventoryData?.stashId,
                        stashSlot: itemSnap.stashSlot || itemSnap.slot,
                        count: amount,
                        x: targetSnap.x,
                        y: targetSnap.y
                    })
                }).catch(() => {});
            };
            if ((itemSnap.count || 1) <= 1) {
                withdrawFromStash(1);
            } else {
                openDropModal(itemSnap, null, withdrawFromStash);
            }
            cancelDrag();
            return;
        }
        if (playerTarget.type !== 'slot') {
            cancelDrag();
            return;
        }
        // Check merge from ground into same-name player item
        const targetItem = getItemAtCell(inventoryData?.items || [], playerTarget.x, playerTarget.y);
        if (canItemsMerge(draggedItem, targetItem)) {
            fetch(`https://${GetParentResourceName()}/mergeGroundItem`, {
                method: 'POST',
                body: JSON.stringify({
                    groundSlot: draggedItem.slot,
                    toSlot: targetItem.slot
                })
            }).catch(() => {});
        } else {
            const valid = !checkCollision(playerTarget.x, playerTarget.y, size.w, size.h, inventoryData?.items || []);
            if (valid) {
                fetch(`https://${GetParentResourceName()}/pickupItem`, {
                    method: 'POST',
                    body: JSON.stringify({
                        groundSlot: draggedItem.slot,
                        x: playerTarget.x,
                        y: playerTarget.y
                    })
                }).catch(() => {});
            }
        }
    }

    cancelDrag();
}

const contextConnector = document.getElementById('context-connector');
const playersSubmenu = document.getElementById('players-submenu');
const playersList = document.getElementById('players-list');
let nearbyPlayers = [];
let contextItemElement = null;

function showContextMenu(e, item, source, itemEl) {
    e.preventDefault();
    e.stopPropagation();

    if (source !== 'player') return;

    selectedItem = { ...item, source };
    contextItemElement = itemEl;

    const itemRect = itemEl.getBoundingClientRect();

    // Position at the bottom-right corner
    const menuX = itemRect.right;
    const menuY = itemRect.bottom;

    contextMenu.style.left = menuX + 'px';
    contextMenu.style.top = menuY + 'px';
    contextMenu.classList.remove('hidden');

    playersSubmenu.classList.add('hidden');

    fetch(`https://${GetParentResourceName()}/getNearbyPlayers`, {
        method: 'POST',
        body: JSON.stringify({})
    }).catch(() => { });
}

function hideContextMenu() {
    contextMenu.classList.add('hidden');
    playersSubmenu.classList.add('hidden');
    selectedItem = null;
    contextItemElement = null;
}

// â”€â”€ UNIVERSAL AMOUNT MODAL â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Replaces all window.prompt / window.alert for drop, split, give, drag-drop
(function initAmountModal() {
    const overlay       = document.getElementById('amount-modal');
    const modalIcon     = document.getElementById('amount-modal-icon');
    const modalTitle    = document.getElementById('amount-modal-title');
    const slider        = document.getElementById('amount-slider');
    const numInput      = document.getElementById('amount-input');
    const remainEl      = document.getElementById('amount-remain');
    const takeEl        = document.getElementById('amount-take');
    const labelRemain   = document.getElementById('amount-label-remain');
    const labelTake     = document.getElementById('amount-label-take');
    const stacksRow     = document.getElementById('amount-stacks-row');
    const itemNameEl    = document.getElementById('amount-item-name');
    const itemTotalEl   = document.getElementById('amount-item-total');
    const itemIconEl    = document.getElementById('amount-item-icon');
    const btnMinus      = document.getElementById('amount-minus');
    const btnPlus       = document.getElementById('amount-plus');
    const btnCancel     = document.getElementById('amount-cancel');
    const btnConfirm    = document.getElementById('amount-confirm');
    const confirmIcon   = document.getElementById('amount-confirm-icon');
    const confirmLabel  = document.getElementById('amount-confirm-label');

    let currentCb  = null;
    let currentMax = 1;
    let currentMin = 1;

    function clamp(v) {
        return Math.max(currentMin, Math.min(currentMax, Math.floor(Number(v)) || currentMin));
    }

    function syncUI(val) {
        val = clamp(val);
        slider.value   = val;
        numInput.value = val;
        takeEl.textContent   = val;
        remainEl.textContent = currentMax + currentMin - val; // total - val for split; max - val + min for others
        // For non-split modes where "remain" = total - taken:
        remainEl.textContent = (Number(itemTotalEl.dataset.total) || currentMax) - val;
    }

    /**
     * openAmountModal(config)
     *   config.item        â€” item object { name, label, count, ... }
     *   config.title       â€” modal header title
     *   config.icon        â€” fa icon class (e.g. 'fa-solid fa-trash-can')
     *   config.confirmText â€” confirm button label
     *   config.confirmIcon â€” fa icon class for confirm btn
     *   config.min         â€” minimum amount (default 1)
     *   config.max         â€” maximum amount (default item.count)
     *   config.defaultVal  â€” initial slider value (default max)
     *   config.labelRemain â€” left stack label (default 'Sisa')
     *   config.labelTake   â€” right stack label (default 'Jumlah')
     *   config.showRemain  â€” show remain stack (default true)
     *   config.callback(amount) â€” called with chosen amount on confirm
     */
    window.openAmountModal = function(config) {
        const item  = config.item;
        const total = Number(item?.count) || 1;

        currentMin = Number.isFinite(config.min) ? config.min : 1;
        currentMax = Number.isFinite(config.max) ? config.max : total;
        currentCb  = config.callback || null;

        // Header
        modalIcon.className  = config.icon || 'fa-solid fa-code-branch';
        modalTitle.textContent = config.title || 'Jumlah';

        // Confirm button
        confirmIcon.className  = config.confirmIcon || 'fa-solid fa-check';
        confirmLabel.textContent = config.confirmText || 'Konfirmasi';

        // Labels
        labelRemain.textContent = config.labelRemain || 'Sisa';
        labelTake.textContent   = config.labelTake   || 'Jumlah';

        // Show/hide remain stack
        stacksRow.style.display = (config.showRemain === false) ? 'none' : '';

        // Item preview
        itemNameEl.textContent = item?.label || item?.name || 'Item';
        itemTotalEl.textContent = `Total: ${total}`;
        itemTotalEl.dataset.total = total;

        itemIconEl.innerHTML = '';
        const img = document.createElement('img');
        img.src = `images/${(item?.name || '').toLowerCase()}.png`;
        img.onerror = () => { img.src = 'images/default.png'; };
        itemIconEl.appendChild(img);

        // Slider range
        slider.min   = currentMin;
        slider.max   = currentMax;
        numInput.min = currentMin;
        numInput.max = currentMax;

        const defVal = Number.isFinite(config.defaultVal) ? config.defaultVal : currentMax;
        syncUI(defVal);

        overlay.classList.remove('hidden');
        numInput.focus();
        numInput.select();
    };

    // Convenience wrappers
    window.openSplitModal = function(item) {
        const total = item.count || 1;
        openAmountModal({
            item,
            title:       'Split Item',
            icon:        'fa-solid fa-code-branch',
            confirmText: 'Split',
            confirmIcon: 'fa-solid fa-code-branch',
            min:         1,
            max:         total - 1,
            defaultVal:  Math.max(1, Math.floor(total / 2)),
            labelRemain: 'Sisa',
            labelTake:   'Dipisah',
            callback(amount) {
                fetch(`https://${GetParentResourceName()}/splitItem`, {
                    method: 'POST',
                    body: JSON.stringify({ name: item.name, count: amount, slot: item.slot })
                }).catch(() => {});
            }
        });
    };

    window.openDropModal = function(item, extra, onConfirm) {
        openAmountModal({
            item,
            title:       'Drop Item',
            icon:        'fa-solid fa-trash-can',
            confirmText: 'Drop',
            confirmIcon: 'fa-solid fa-trash-can',
            min:         1,
            max:         item.count || 1,
            defaultVal:  item.count || 1,
            labelRemain: 'Simpan',
            labelTake:   'Dibuang',
            callback(amount) { onConfirm(amount); }
        });
    };

    window.openGiveModal = function(item, onConfirm) {
        openAmountModal({
            item,
            title:       'Give Item',
            icon:        'fa-solid fa-gift',
            confirmText: 'Give',
            confirmIcon: 'fa-solid fa-gift',
            min:         1,
            max:         item.count || 1,
            defaultVal:  item.count || 1,
            labelRemain: 'Simpan',
            labelTake:   'Diberikan',
            callback(amount) { onConfirm(amount); }
        });
    };

    // â”€â”€ Internal UI wiring â”€â”€
    function doCancel() {
        overlay.classList.add('hidden');
        currentCb = null;
    }

    function doConfirm() {
        const amount = clamp(slider.value);
        overlay.classList.add('hidden');
        if (currentCb) currentCb(amount);
        currentCb = null;
    }

    slider.addEventListener('input', () => syncUI(slider.value));

    numInput.addEventListener('input', () => syncUI(numInput.value));
    numInput.addEventListener('change', () => syncUI(numInput.value));
    numInput.addEventListener('keydown', (e) => {
        if (e.key === 'Enter')  { e.preventDefault(); doConfirm(); }
        if (e.key === 'Escape') { e.preventDefault(); doCancel(); }
    });

    btnMinus.addEventListener('click', () => syncUI(Number(slider.value) - 1));
    btnPlus.addEventListener('click',  () => syncUI(Number(slider.value) + 1));
    btnCancel.addEventListener('click', doCancel);
    btnConfirm.addEventListener('click', doConfirm);
    overlay.addEventListener('click', (e) => { if (e.target === overlay) doCancel(); });
})();

// Wire up context menu option clicks (Use, Drop, Give)
contextMenu.querySelectorAll('.menu-option').forEach(option => {
    option.addEventListener('click', (e) => {
        e.preventDefault();
        e.stopPropagation();

        const action = option.dataset.action;

        if (action === 'use') {
            if (!selectedItem) return;
            fetch(`https://${GetParentResourceName()}/useItem`, {
                method: 'POST',
                body: JSON.stringify({
                    name: selectedItem.name,
                    slot: selectedItem.slot
                })
            }).catch(() => {});
            hideContextMenu();

        } else if (action === 'split') {
            if (!selectedItem) return;
            if ((selectedItem.count || 1) <= 1) {
                // Tidak bisa split, abaikan saja (tidak pakai alert)
                hideContextMenu();
                return;
            }
            openSplitModal(selectedItem);
            hideContextMenu();

        } else if (action === 'drop') {
            if (!selectedItem) return;
            const itemSnap = { ...selectedItem };
            hideContextMenu();
            if ((itemSnap.count || 1) <= 1) {
                fetch(`https://${GetParentResourceName()}/dropItem`, {
                    method: 'POST',
                    body: JSON.stringify({ name: itemSnap.name, count: 1, slot: itemSnap.slot })
                }).catch(() => {});
                return;
            }
            openDropModal(itemSnap, null, (amount) => {
                fetch(`https://${GetParentResourceName()}/dropItem`, {
                    method: 'POST',
                    body: JSON.stringify({ name: itemSnap.name, count: amount, slot: itemSnap.slot })
                }).catch(() => {});
            });

        } else if (action === 'give') {
            // Posisikan submenu di sebelah kanan context menu (fixed positioning)
            const menuRect = contextMenu.getBoundingClientRect();
            playersSubmenu.style.left = (menuRect.right + 4) + 'px';
            playersSubmenu.style.top  = menuRect.top + 'px';
            // Toggle submenu tanpa menutup context menu (selectedItem tetap ada)
            playersSubmenu.classList.toggle('hidden');
        }
    });
});

function updateNearbyPlayers(players) {
    nearbyPlayers = players || [];
    renderPlayersList();
}


function renderPlayersList() {
    playersList.innerHTML = '';

    if (nearbyPlayers.length === 0) {
        playersList.innerHTML = '<div class="no-players">No players nearby</div>';
        return;
    }

    nearbyPlayers.forEach(player => {
        const playerEl = document.createElement('div');
        playerEl.className = 'player-option';
        const distanceText = player.distance < 1 ? '<1m' : `${Math.floor(player.distance)}m`;
        const infoDiv = document.createElement('div');
        infoDiv.className = 'player-info';
        const icon = document.createElement('i');
        icon.className = 'fa-solid fa-user';
        infoDiv.appendChild(icon);
        const nameSpan = document.createElement('span');
        nameSpan.className = 'player-name';
        nameSpan.textContent = player.name;
        infoDiv.appendChild(nameSpan);
        playerEl.appendChild(infoDiv);
        const distSpan = document.createElement('span');
        distSpan.className = 'player-distance';
        distSpan.textContent = distanceText;
        playerEl.appendChild(distSpan);
        playerEl.addEventListener('click', () => giveItemToPlayer(player.id));
        playersList.appendChild(playerEl);
    });
}

function giveItemToPlayer(playerId) {
    if (!selectedItem) return;
    const itemSnap = { ...selectedItem };
    hideContextMenu();

    const doGive = (amount) => {
        console.log('[INVENTORY-JS] Giving item to player:', playerId, itemSnap.name);
        fetch(`https://${GetParentResourceName()}/giveItem`, {
            method: 'POST',
            body: JSON.stringify({
                name:         itemSnap.name,
                count:        amount,
                slot:         itemSnap.slot,
                targetPlayer: playerId
            })
        });
    };

    if ((itemSnap.count || 1) <= 1) {
        doGive(1);
        return;
    }
    openGiveModal(itemSnap, doGive);
}

window.addEventListener('message', (event) => {
    const data = event.data;
    switch (data.action) {
        case 'open':
            openInventory(data.inventory || data);
            break;
        case 'update':
            updateInventory(data.inventory || data);
            break;
        case 'close':
            forceClose();
            break;
        case 'updateGround':
            updateGroundItems(data.items || []);
            break;
        case 'updateNearbyPlayers':
            updateNearbyPlayers(data.players || []);
            break;
        case 'updateHotbar':
            // Update hotbar using full inventory data (works even when inventory is closed)
            if (data.inventory) {
                // Store items and itemsData globally
                if (data.inventory.items) {
                    window.latestInventoryItems = data.inventory.items;
                }
                if (data.inventory.itemsData) {
                    itemsData = data.inventory.itemsData;
                }
                // Update hotbar display
                if (window.latestInventoryItems) {
                    assignHotkeysToSlots(window.latestInventoryItems);
                }
            }
            break;
        case 'openLootContainer':
            openLootContainer(data);
            break;
        case 'closeLootContainer':
            closeLootContainer();
            break;
        case 'setHotbarVisible':
            setHotbarVisible(data.visible);
            break;
    }
});

function forceClose() {
    if (isContainerMode) closeLootContainer();
    container.classList.add('hidden');
    if (typeof window.forceCloseVehicleShop === 'function') {
        window.forceCloseVehicleShop();
    } else if (vehicleShopContainer) {
        vehicleShopContainer.classList.add('hidden');
    }
    hideContextMenu();
    hideDragPreview();
    updateItemInfo(null);
    if (isDragging) cancelDrag();
}

const hotbarContainer = document.getElementById('hotbar-container');
let hotbarData = {};

function setHotbarVisible(visible) {
    if (!hotbarContainer) return;
    hotbarContainer.classList.toggle('hidden', visible === false);
}

function setupHotbarDragAndDrop() {
    const hotbarSlots = document.querySelectorAll('.hotbar-slot');

    hotbarSlots.forEach(slot => {
        slot.addEventListener('mouseenter', () => {
            if (isDragging && dragSource === 'player') {
                slot.classList.add('drag-over');
            }
        });

        slot.addEventListener('mouseleave', () => {
            slot.classList.remove('drag-over');
        });

        slot.addEventListener('mouseup', (e) => {
            if (!isDragging || !draggedItem || dragSource !== 'player') return;

            e.stopPropagation();
            slot.classList.remove('drag-over');

            const slotNumber = parseInt(slot.dataset.slot);
            const itemDef = itemsData[draggedItem.name] || {};

            hotbarData[slotNumber] = {
                name: draggedItem.name,
                slot: draggedItem.slot,
                data: draggedItem
            };

            fetch(`https://${GetParentResourceName()}/setHotbarSlot`, {
                method: 'POST',
                body: JSON.stringify({
                    slot: slotNumber,
                    item: hotbarData[slotNumber]
                })
            });

            renderHotbarSlot(slot, hotbarData[slotNumber], itemDef);

            cancelDrag();
        });

        slot.addEventListener('contextmenu', (e) => {
            e.preventDefault();
            const slotNumber = parseInt(slot.dataset.slot);

            if (hotbarData[slotNumber]) {
                delete hotbarData[slotNumber];

                fetch(`https://${GetParentResourceName()}/clearHotbarSlot`, {
                    method: 'POST',
                    body: JSON.stringify({ slot: slotNumber })
                });

                clearHotbarSlot(slot);
            }
        });
    });
}

function renderHotbarSlot(slot, item, itemDef) {
    const existingImg = slot.querySelector('.hotbar-item-image');
    const existingCount = slot.querySelector('.hotbar-item-count');
    const existingRarity = slot.querySelector('.hotbar-rarity-bar');

    if (existingImg) existingImg.remove();
    if (existingCount) existingCount.remove();
    if (existingRarity) existingRarity.remove();

    slot.className = 'hotbar-slot has-item';

    if (!item) return;

    const rarity = itemDef.rarity || 'common';
    slot.dataset.rarity = rarity;

    const img = document.createElement('img');
    img.className = 'hotbar-item-image';
    img.src = `images/${itemDef.image || 'default.png'}`;
    img.alt = itemDef.label || item.name;

    const count = document.createElement('span');
    count.className = 'hotbar-item-count';
    count.textContent = item.data?.count || 1;

    const rarityBar = document.createElement('div');
    rarityBar.className = 'hotbar-rarity-bar rarity-' + rarity;

    slot.appendChild(img);
    slot.appendChild(count);
    slot.appendChild(rarityBar);
}

function clearHotbarSlot(slot) {
    const img = slot.querySelector('.hotbar-item-image');
    const count = slot.querySelector('.hotbar-item-count');
    const rarityBar = slot.querySelector('.hotbar-rarity-bar');

    if (img) img.remove();
    if (count) count.remove();
    if (rarityBar) rarityBar.remove();

    slot.className = 'hotbar-slot';
    delete slot.dataset.rarity;
}

function updateHotbar(hotbar) {
    hotbarData = hotbar || {};

    const hotbarSlots = document.querySelectorAll('.hotbar-slot');
    hotbarSlots.forEach(slot => {
        const slotNumber = parseInt(slot.dataset.slot);
        const item = hotbarData[slotNumber];

        if (item) {
            const itemDef = itemsData[item.name] || {};
            renderHotbarSlot(slot, item, itemDef);
        } else {
            clearHotbarSlot(slot);
        }
    });
}

function GetParentResourceName() {
    if (window.location.hostname === '') {
        return 'corex-inventory';
    }
    // Remove 'cfx-nui-' prefix that FiveM adds. Cached so we don't pay the
    // string-replace cost on every fetch (called from drag/drop, hotbar, etc).
    if (!GetParentResourceName._cached) {
        GetParentResourceName._cached = window.location.hostname.replace('cfx-nui-', '');
    }
    return GetParentResourceName._cached;
}

setupHotbarDragAndDrop();
initializeUI();

/* ========== LOOT CONTAINER MODE ========== */

let isContainerMode = false;
let containerData = null;
let revealTimers = [];

function playRevealSound() {
    try {
        const ctx = new (window.AudioContext || window.webkitAudioContext)();
        const osc = ctx.createOscillator();
        const gain = ctx.createGain();
        osc.connect(gain);
        gain.connect(ctx.destination);
        osc.frequency.setValueAtTime(800, ctx.currentTime);
        osc.frequency.exponentialRampToValueAtTime(1200, ctx.currentTime + 0.05);
        osc.frequency.exponentialRampToValueAtTime(600, ctx.currentTime + 0.15);
        gain.gain.setValueAtTime(0.15, ctx.currentTime);
        gain.gain.exponentialRampToValueAtTime(0.01, ctx.currentTime + 0.2);
        osc.start(ctx.currentTime);
        osc.stop(ctx.currentTime + 0.2);
    } catch (e) {}
}

function openLootContainer(data) {
    isContainerMode = true;
    containerData = data;

    const dropTitle = document.getElementById('drop-title');
    const dropHint = document.getElementById('drop-hint');
    const dropIcon = document.getElementById('drop-icon');
    const shopMoney = document.getElementById('shop-money');

    dropTitle.textContent = data.containerName || 'Loot Container';
    dropHint.classList.add('hidden');
    shopMoney.classList.add('hidden');
    dropIcon.className = 'fa-solid fa-box-open hex-inner-icon';

    const dropGridEl = document.getElementById('drop-grid');
    dropGridEl.querySelectorAll('.item').forEach(el => el.remove());

    if (!data.items || data.items.length === 0) return;

    data.items.forEach((item, index) => {
        const itemDef = itemsData[item.name] || { size: { w: 1, h: 1 }, label: item.name, weight: 0 };
        const w = itemDef.size?.w || 1;
        const h = itemDef.size?.h || 1;
        const rarity = itemDef.rarity || item.rarity || 'common';

        const x = item.x || ((index % CONFIG.gridCols) + 1);
        const y = item.y || (Math.floor(index / CONFIG.gridCols) + 1);

        const left = (x - 1) * (CONFIG.cellSize + CONFIG.gapSize);
        const top = (y - 1) * (CONFIG.cellSize + CONFIG.gapSize);
        const width = w * CONFIG.cellSize + (w - 1) * CONFIG.gapSize;
        const height = h * CONFIG.cellSize + (h - 1) * CONFIG.gapSize;

        const el = document.createElement('div');
        el.className = `item rarity-${rarity} loot-pending`;
        el.style.left = left + 'px';
        el.style.top = top + 'px';
        el.style.width = width + 'px';
        el.style.height = height + 'px';
        el.dataset.containerIndex = index;
        el.dataset.source = 'container';
        el.dataset.name = item.name;
        el.dataset.count = item.count || 1;
        el.dataset.revealed = 'false';
        el.style.pointerEvents = 'none';

        const imgSrc = itemDef.image ? `images/${itemDef.image}` : (item.image || 'images/default.png');
        const totalWeight = ((itemDef.weight || 0) * (item.count || 1)).toFixed(2);

        el.innerHTML = '';
        const lootFrag = document.createDocumentFragment();
        const lr = document.createElement('span');
        lr.className = 'item-rarity';
        lr.textContent = rarity.toUpperCase();
        lootFrag.appendChild(lr);
        const lq = document.createElement('span');
        lq.className = 'item-qty';
        lq.textContent = item.count || 1;
        lootFrag.appendChild(lq);
        const lw = document.createElement('span');
        lw.className = 'item-weight';
        lw.textContent = totalWeight + 'kg';
        lootFrag.appendChild(lw);
        const lImg = document.createElement('img');
        lImg.src = imgSrc;
        lImg.alt = itemDef.label || item.name || '';
        lImg.onerror = function() { this.onerror = null; this.src = 'images/default.png'; };
        lootFrag.appendChild(lImg);
        const lName = document.createElement('span');
        lName.className = 'item-name';
        lName.textContent = item.label || itemDef.label || item.name;
        lootFrag.appendChild(lName);
        el.appendChild(lootFrag);

        const shimmer = document.createElement('div');
        shimmer.className = 'loot-shimmer';
        el.appendChild(shimmer);

        el.addEventListener('click', () => {
            if (el.dataset.revealed !== 'true') return;
            if (el.dataset.taken === 'true') return;
            el.dataset.taken = 'true';

            fetch(`https://${GetParentResourceName()}/takeLootItem`, {
                method: 'POST',
                body: JSON.stringify({
                    containerId: containerData?.containerId,
                    itemIndex: item.index != null ? item.index : index,
                    itemName: item.name,
                    itemCount: item.count || 1
                })
            }).catch(() => {});

            el.style.transition = 'opacity 0.3s ease, transform 0.3s ease';
            el.style.opacity = '0';
            el.style.transform = 'scale(0.5)';
            setTimeout(() => el.remove(), 300);
        });

        dropGridEl.appendChild(el);

        const revealDelay = (data.revealDelay || 1800) * (index + 1);
        const timer = setTimeout(() => {
            el.classList.add('loot-revealing');
            shimmer.classList.add('revealing');

            setTimeout(() => {
                shimmer.remove();
                el.classList.remove('loot-pending', 'loot-revealing');
                el.classList.add('loot-revealed');
                el.dataset.revealed = 'true';
                el.style.pointerEvents = 'auto';
                playRevealSound();
            }, 600);
        }, revealDelay);

        revealTimers.push(timer);
    });
}

function closeLootContainer() {
    isContainerMode = false;
    containerData = null;
    revealTimers.forEach(t => clearTimeout(t));
    revealTimers = [];

    const dropTitle = document.getElementById('drop-title');
    const dropHint = document.getElementById('drop-hint');
    const dropIcon = document.getElementById('drop-icon');

    dropTitle.textContent = 'Ground';
    dropHint.classList.remove('hidden');
    dropIcon.className = 'fa-solid fa-arrow-down hex-inner-icon';
}
