/* ============================================================
   COREX INVENTORY — FILTER & SORT  v2.1 (BUGFIX)
   ============================================================
   CHANGELOG v2.1:
   [FIX-SORT-1] wireToolbar() called once from DOMContentLoaded;
                no race-condition retry loops.
   [FIX-SORT-2] pointer-events:auto forced on all toolbar elements
                so grid overlay can never block them.
   [FIX-SORT-3] applyFilter exposed as window.applyInventoryFilter
                for script.js to call after every renderItems().
   [FIX-SORT-4] MutationObserver fires on full re-renders too.
   [FIX-SORT-5] restorePositions falls back to data-x/data-y
                after full re-renders when _origPos is empty.
   ============================================================ */
(function () {
    'use strict';

    var STEP        = 70;   // 64px cell + 6px gap
    var searchQuery = '';
    var sortMode    = 'default';
    var gridCols    = 8;
    var gridRows    = 10;
    var _origPos    = {};   // slot-key -> { left, top }
    var _busy       = false;

    var RARITY_RANK = { common: 0, uncommon: 1, rare: 2, epic: 3, legendary: 4, mythic: 5 };

    // Listen for grid size changes from FiveM
    window.addEventListener('message', function (e) {
        var d = e.data || {};
        if (d.action === 'open') {
            var grid = (d.inventory && d.inventory.grid) || d.grid;
            if (grid) {
                gridCols = grid.w || 8;
                gridRows = grid.h || 10;
            }
            resetFilter();
        }
        // Re-apply after DOM updates
        if (d.action === 'update' || d.action === 'open') {
            requestAnimationFrame(function () {
                if (searchQuery || sortMode !== 'default') {
                    applyFilter();
                }
            });
        }
    });

    // Helpers
    function itemSize(el) {
        var w = Math.max(1, Math.round((parseInt(el.style.width,  10) + 6) / STEP));
        var h = Math.max(1, Math.round((parseInt(el.style.height, 10) + 6) / STEP));
        return { w: w, h: h };
    }

    function itemRarity(el) {
        for (var r in RARITY_RANK) {
            if (el.classList.contains('rarity-' + r)) return RARITY_RANK[r];
        }
        return 0;
    }

    function itemLabel(el) {
        var n = el.querySelector('.item-name');
        return (n ? n.textContent : (el.dataset.name || '')).toLowerCase().trim();
    }

    function itemDescription(el) {
        return [
            el.getAttribute('title') || '',
            el.dataset.name || '',
            el.dataset.label || '',
            el.dataset.description || '',
            itemLabel(el)
        ].join(' ').toLowerCase();
    }

    function itemWeight(el) {
        var w = el.querySelector('.item-weight');
        return w ? parseFloat(w.textContent) || 0 : 0;
    }

    // Bin-packing (row-major)
    function lockedSlotsFromHotkeys() {
        var mapping = window.hotkeyMapping || [];
        var locked = new Set();
        for (var slotNum = 1; slotNum <= 6; slotNum++) {
            var m = mapping[slotNum];
            if (!m || m.type !== 'item' || !m.item) continue;
            if (m.item.slot != null) locked.add(String(m.item.slot));
        }
        return locked;
    }

    function pack(sorted, lockedEls) {
        var occ = new Set();

        function fits(c, r, w, h) {
            if (c + w - 1 > gridCols || r + h - 1 > gridRows) return false;
            for (var dr = 0; dr < h; dr++)
                for (var dc = 0; dc < w; dc++)
                    if (occ.has((c + dc) + ',' + (r + dr))) return false;
            return true;
        }

        function occupy(c, r, w, h) {
            for (var dr = 0; dr < h; dr++)
                for (var dc = 0; dc < w; dc++)
                    occ.add((c + dc) + ',' + (r + dr));
        }

        // Pre-occupy locked (hotbar 1-6) items so they never get moved-over.
        (lockedEls || []).forEach(function (el) {
            var x = parseInt(el.dataset.x, 10) || 1;
            var y = parseInt(el.dataset.y, 10) || 1;
            var s = itemSize(el);
            occupy(x, y, s.w, s.h);
        });

        sorted.forEach(function (item) {
            var placed = false;
            outer:
            for (var row = 1; row <= gridRows; row++) {
                for (var col = 1; col <= gridCols; col++) {
                    if (fits(col, row, item.w, item.h)) {
                        occupy(col, row, item.w, item.h);
                        item.el.style.left = ((col - 1) * STEP) + 'px';
                        item.el.style.top  = ((row - 1) * STEP) + 'px';
                        placed = true;
                        break outer;
                    }
                }
            }
            if (!placed) item.el.style.display = 'none';
        });
    }

    // [FIX-SORT-3] Apply search + sort — also exported globally
    function applyFilter() {
        var grid = document.getElementById('player-grid');
        if (!grid) return;

        var items = Array.from(grid.querySelectorAll('.item:not(.dragging)'));
        if (!items.length) return;

        _busy = true;

        var lockedSlots = lockedSlotsFromHotkeys();
        var matched = [];
        var lockedMatched = [];
        items.forEach(function (el) {
            var haystack = itemDescription(el);
            var match = !searchQuery || haystack.indexOf(searchQuery) !== -1;
            var isLocked = lockedSlots.has(String(el.dataset.slot || ''));

            el.style.display = match ? '' : 'none';
            el.style.opacity = match ? '' : '0';
            el.style.pointerEvents = match ? 'auto' : 'none';

            if (match) {
                if (isLocked) lockedMatched.push(el);
                else matched.push(el);
            }
        });

        if (!matched.length) {
            _busy = false;
            return;
        }

        var data = matched.map(function (el) {
            var s = itemSize(el);
            return { el: el, w: s.w, h: s.h };
        });

        if (sortMode !== 'default') {
            data.sort(function (a, b) {
                switch (sortMode) {
                    case 'name':    return itemLabel(a.el).localeCompare(itemLabel(b.el));
                    case 'weight+': return itemWeight(a.el) - itemWeight(b.el);
                    case 'weight-': return itemWeight(b.el) - itemWeight(a.el);
                    case 'rarity':  return itemRarity(b.el) - itemRarity(a.el);
                    default:        return 0;
                }
            });
        }

        if (searchQuery || sortMode !== 'default') {
            pack(data, lockedMatched);
        }
        _busy = false;
    }

    // [FIX-SORT-5] Restore original grid positions
    function restorePositions() {
        var grid = document.getElementById('player-grid');
        if (!grid) return;

        grid.querySelectorAll('.item').forEach(function (el) {
            var key  = el.dataset.slot + '_' + el.dataset.x + '_' + el.dataset.y;
            var orig = _origPos[key];

            if (orig) {
                el.style.left = orig.left;
                el.style.top  = orig.top;
            } else {
                // Fallback: recompute from data attributes after full re-render
                var x = parseInt(el.dataset.x, 10) || 1;
                var y = parseInt(el.dataset.y, 10) || 1;
                el.style.left = ((x - 1) * STEP) + 'px';
                el.style.top  = ((y - 1) * STEP) + 'px';
            }

            el.style.display       = '';
            el.style.opacity       = '';
            el.style.pointerEvents = 'auto';
        });

        if (searchQuery || sortMode !== 'default') {
            applyFilter();
        }
    }

    function resetFilter() {
        searchQuery = '';
        sortMode    = 'default';
        _origPos    = {};

        var inp = document.getElementById('inv-search-input');
        var clr = document.getElementById('inv-search-clear');
        if (inp) inp.value = '';
        if (clr) clr.classList.add('hidden');

        document.querySelectorAll('.inv-sort-btn').forEach(function (b) {
            b.classList.remove('active');
        });
        var def = document.querySelector('.inv-sort-btn[data-sort="default"]');
        if (def) def.classList.add('active');
    }

    // [FIX-SORT-4] Observe childList including removals (full re-render detection)
    function watchGrid() {
        var grid = document.getElementById('player-grid');
        if (!grid) return;

        new MutationObserver(function (mutations) {
            var hasAdditions = mutations.some(function (m) {
                return m.addedNodes.length > 0;
            });
            if (!hasAdditions) return;

            if (!_busy) {
                mutations.forEach(function (m) {
                    m.addedNodes.forEach(function (n) {
                        if (n.nodeType === 1 && n.classList && n.classList.contains('item')) {
                            var key = n.dataset.slot + '_' + n.dataset.x + '_' + n.dataset.y;
                            _origPos[key] = { left: n.style.left, top: n.style.top };
                        }
                    });
                });
            }

            requestAnimationFrame(function () {
                if (searchQuery || sortMode !== 'default') {
                    applyFilter();
                }
            });
        }).observe(grid, { childList: true });
    }

    // [FIX-SORT-1] Wire toolbar exactly once; DOM elements exist in static HTML
    function wireToolbar() {
        var inp = document.getElementById('inv-search-input');
        var clr = document.getElementById('inv-search-clear');

        if (!inp || !clr) {
            setTimeout(wireToolbar, 100);
            return;
        }

        // [FIX-SORT-2] Force pointer-events so no parent overlay can block them
        inp.style.pointerEvents = 'auto';
        clr.style.pointerEvents = 'auto';
        document.querySelectorAll('.inv-sort-btn').forEach(function (btn) {
            btn.style.pointerEvents = 'auto';
        });
        var toolbar = document.getElementById('inv-toolbar');
        if (toolbar) toolbar.style.pointerEvents = 'auto';

        inp.addEventListener('input', function () {
            searchQuery = inp.value.trim().toLowerCase();
            clr.classList.toggle('hidden', !searchQuery);
            if (searchQuery || sortMode !== 'default') {
                applyFilter();
            } else {
                restorePositions();
            }
        });

        clr.addEventListener('click', function (e) {
            e.stopPropagation();
            inp.value   = '';
            searchQuery = '';
            clr.classList.add('hidden');
            if (sortMode !== 'default') {
                applyFilter();
            } else {
                restorePositions();
            }
        });

        inp.addEventListener('mousedown',   function (e) { e.stopPropagation(); });
        inp.addEventListener('contextmenu', function (e) { e.stopPropagation(); });

        inp.addEventListener('keydown', function (e) {
            if (e.key === 'Escape' && searchQuery) {
                e.stopPropagation();
                clr.click();
            }
        });

        document.querySelectorAll('.inv-sort-btn').forEach(function (btn) {
            btn.addEventListener('mousedown', function (e) { e.stopPropagation(); });
            btn.addEventListener('click', function (e) {
                e.stopPropagation();
                e.preventDefault();
                var s = btn.dataset.sort;

                sortMode = (sortMode === s && s !== 'default') ? 'default' : s;

                document.querySelectorAll('.inv-sort-btn').forEach(function (b) {
                    b.classList.remove('active');
                });
                var activeBtn = document.querySelector('.inv-sort-btn[data-sort="' + sortMode + '"]');
                if (activeBtn) activeBtn.classList.add('active');

                if (sortMode === 'default') {
                    restorePositions();
                } else {
                    applyFilter();
                }
            });
        });

        watchGrid();
    }

    // [FIX-SORT-3] Global exports for script.js integration
    window.applyInventoryFilter = applyFilter;
    window.resetInventoryFilter = resetFilter;

    // Boot
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', wireToolbar);
    } else {
        wireToolbar();
    }

})();
