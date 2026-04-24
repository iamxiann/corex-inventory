(function () {
    const overlay = document.getElementById('vehicle-shop-container');
    const titleEl = document.getElementById('vehicle-shop-title');
    const eyebrowEl = document.getElementById('vehicle-shop-eyebrow');
    const moneyEl = document.getElementById('vehicle-shop-money');
    const searchEl = document.getElementById('vehicle-shop-search');
    const tabsEl = document.getElementById('vehicle-shop-tabs');
    const sortEl = document.getElementById('vehicle-shop-sort');
    const sortBtn = document.getElementById('vehicle-shop-sort-btn');
    const sortLabel = document.getElementById('vehicle-shop-sort-label');
    const gridEl = document.getElementById('vehicle-shop-grid');
    const closeBtn = document.getElementById('vehicle-shop-close');
    const countCurrentEl = document.getElementById('vehicle-shop-count-current');
    const countTotalEl = document.getElementById('vehicle-shop-count-total');

    const icons = {
        frame: '<i class="fa-solid fa-vector-square"></i>',
        weight: '<i class="fa-solid fa-weight-hanging"></i>',
        drive: '<i class="fa-solid fa-gear"></i>',
        brakes: '<i class="fa-solid fa-hand"></i>',
        speed: '<i class="fa-solid fa-gauge-high"></i>'
    };

    const statusLabel = {
        available: 'AVAILABLE',
        limited: 'LIMITED',
        reserved: 'RESERVED'
    };

    const state = {
        open: false,
        catalog: null,
        vehicles: [],
        activeCategory: 'all',
        activeSort: 'featured',
        searchQuery: ''
    };

    function normalize(value) {
        return String(value || '').trim().toLowerCase();
    }

    function formatMoney(value) {
        const amount = Number(value) || 0;
        return '$' + amount.toLocaleString();
    }

    function closeVehicleShopUi() {
        state.open = false;
        overlay.classList.add('hidden');
        sortEl.classList.remove('open');
    }

    window.forceCloseVehicleShop = closeVehicleShopUi;

    function getCategories() {
        const found = [{ id: 'all', label: 'All' }];
        const used = { all: true };

        state.vehicles.forEach((vehicle) => {
            const key = normalize(vehicle.category);
            if (!key || used[key]) return;
            used[key] = true;
            found.push({
                id: key,
                label: vehicle.category.charAt(0).toUpperCase() + vehicle.category.slice(1)
            });
        });

        return found;
    }

    function renderTabs() {
        const categories = getCategories();
        tabsEl.innerHTML = categories.map((category) => {
            const active = state.activeCategory === category.id ? ' active' : '';
            return `<button class="tab${active}" type="button" data-cat="${category.id}">${category.label}</button>`;
        }).join('');
    }

    function getFilteredVehicles() {
        let list = state.vehicles.slice();

        if (state.activeCategory !== 'all') {
            list = list.filter((vehicle) => normalize(vehicle.category) === state.activeCategory);
        }

        if (state.searchQuery) {
            list = list.filter((vehicle) => {
                const specs = vehicle.specs || {};
                const haystack = [
                    vehicle.label,
                    vehicle.subtitle,
                    vehicle.description,
                    vehicle.category,
                    specs.frame,
                    specs.weight,
                    specs.drive,
                    specs.brakes,
                    specs.topSpeed
                ].join(' ').toLowerCase();
                return haystack.includes(state.searchQuery);
            });
        }

        if (state.activeSort === 'lowhigh') {
            list.sort((a, b) => (a.price || 0) - (b.price || 0));
        } else if (state.activeSort === 'highlow') {
            list.sort((a, b) => (b.price || 0) - (a.price || 0));
        }

        return list;
    }

    function createSpec(label, value, icon) {
        return `
            <div class="spec">
                <span class="spec-icon">${icon}</span>
                <div class="spec-content">
                    <div class="spec-label">${label}</div>
                    <div class="spec-value">${value || '-'}</div>
                </div>
            </div>
        `;
    }

    function renderVehicles() {
        const list = getFilteredVehicles();
        const total = state.vehicles.length;
        const purchaseLabel = (state.catalog && state.catalog.purchaseLabel) || 'Deploy Bike';

        countCurrentEl.textContent = String(list.length).padStart(2, '0');
        countTotalEl.textContent = String(total).padStart(2, '0');

        if (list.length === 0) {
            gridEl.innerHTML = '<div class="empty-state">No bikes match the current filter.</div>';
            return;
        }

        gridEl.innerHTML = list.map((vehicle) => {
            const specs = vehicle.specs || {};
            const status = normalize(vehicle.status || 'available');
            const disabled = status === 'reserved' ? 'disabled' : '';
            return `
                <article class="card">
                    <div class="card-media">
                        <img class="bike-img" src="${vehicle.image || ''}" alt="${vehicle.label || vehicle.model}" loading="lazy" onerror="this.style.visibility='hidden'" />
                    </div>
                    <div class="card-body">
                        <div class="badge-row">
                            <span class="badge status ${status}">
                                <span class="dot"></span>${statusLabel[status] || 'AVAILABLE'}
                            </span>
                            <span class="badge category">${String(vehicle.category || 'bike').toUpperCase()}</span>
                        </div>

                        <div class="card-header">
                            <div>
                                <div class="card-title">${vehicle.label || vehicle.model}</div>
                                <div class="card-subtitle">${vehicle.subtitle || ''}</div>
                            </div>
                            <div class="price">${formatMoney(vehicle.price)}</div>
                        </div>

                        <div class="card-desc">${vehicle.description || ''}</div>

                        <div class="specs">
                            ${createSpec('Frame', specs.frame, icons.frame)}
                            ${createSpec('Weight', specs.weight, icons.weight)}
                            ${createSpec('Drive', specs.drive, icons.drive)}
                            ${createSpec('Brakes', specs.brakes, icons.brakes)}
                            ${createSpec('Top speed', specs.topSpeed, icons.speed)}
                        </div>

                        <div class="card-footer">
                            <button class="action-btn" type="button" data-model="${vehicle.model}" ${disabled}>${purchaseLabel}</button>
                        </div>
                    </div>
                </article>
            `;
        }).join('');
    }

    function openVehicleShop(data) {
        state.open = true;
        state.catalog = data.catalog || {};
        state.vehicles = Array.isArray(state.catalog.vehicles) ? state.catalog.vehicles : [];
        state.activeCategory = 'all';
        state.activeSort = 'featured';
        state.searchQuery = '';

        titleEl.textContent = data.shopName || state.catalog.label || 'Bike Rental';
        eyebrowEl.textContent = state.catalog.subtitle || 'BASIC TRANSPORT';
        moneyEl.textContent = formatMoney(data.playerMoney || 0);
        searchEl.value = '';
        sortLabel.textContent = 'Featured';
        sortEl.classList.remove('open');

        renderTabs();
        renderVehicles();
        overlay.classList.remove('hidden');
    }

    tabsEl.addEventListener('click', (event) => {
        const button = event.target.closest('[data-cat]');
        if (!button) return;
        state.activeCategory = button.dataset.cat;
        renderTabs();
        renderVehicles();
    });

    sortBtn.addEventListener('click', (event) => {
        event.stopPropagation();
        sortEl.classList.toggle('open');
    });

    document.addEventListener('click', () => {
        sortEl.classList.remove('open');
    });

    sortEl.querySelectorAll('.sort-option').forEach((option) => {
        option.addEventListener('click', (event) => {
            event.stopPropagation();
            sortEl.querySelectorAll('.sort-option').forEach((entry) => entry.classList.remove('selected'));
            option.classList.add('selected');
            state.activeSort = option.dataset.sort;
            sortLabel.textContent = option.querySelector('span').textContent;
            sortEl.classList.remove('open');
            renderVehicles();
        });
    });

    searchEl.addEventListener('input', (event) => {
        state.searchQuery = normalize(event.target.value);
        renderVehicles();
    });

    closeBtn.addEventListener('click', () => {
        fetch(`https://${GetParentResourceName()}/close`, {
            method: 'POST',
            body: JSON.stringify({})
        }).catch(() => {});
    });

    gridEl.addEventListener('click', (event) => {
        const button = event.target.closest('[data-model]');
        if (!button) return;

        fetch(`https://${GetParentResourceName()}/purchaseVehicleShopItem`, {
            method: 'POST',
            body: JSON.stringify({ model: button.dataset.model })
        }).catch(() => {});
    });

    window.addEventListener('message', (event) => {
        const data = event.data || {};
        if (data.action === 'openVehicleShop') {
            openVehicleShop(data);
        } else if (data.action === 'updateVehicleShopMoney') {
            moneyEl.textContent = formatMoney(data.playerMoney || 0);
        } else if (data.action === 'close') {
            closeVehicleShopUi();
        }
    });
})();
