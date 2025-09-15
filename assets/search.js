if (!window.searchNamespace) window.searchNamespace = {};

// Filter search results
function filterSearchResults(data, searchTerm, limit = 10) {
  return data
    .filter(
      (doc) =>
        doc.title.toLowerCase().includes(searchTerm) ||
        doc.content.toLowerCase().includes(searchTerm),
    )
    .slice(0, limit);
}

document.addEventListener("DOMContentLoaded", function () {
  // Search page specific functionality
  const searchPageInput = document.getElementById("search-page-input");
  if (searchPageInput) {
    // Load search data for search page
    fetch("assets/search-data.json")
      .then((response) => response.json())
      .then((data) => {
        // Store search data in a unique namespace
        window.searchNamespace.data = data;

        // Set up event listener
        searchPageInput.addEventListener("input", function () {
          performSearch(this.value);
        });

        // Perform search if URL has query
        const params = new URLSearchParams(window.location.search);
        const query = params.get("q");
        if (query) {
          searchPageInput.value = query;
          performSearch(query);
        }
      })
      .catch((error) => {
        console.error("Error loading search data:", error);
        const resultsContainer = document.getElementById("search-page-results");
        if (resultsContainer) {
          resultsContainer.innerHTML = "<p>Error loading search data</p>";
        }
      });
  }

  // Desktop Sidebar Toggle
  const searchInput = document.getElementById("search-input");
  if (searchInput) {
    const searchResults = document.getElementById("search-results");

    // Load search data
    fetch("assets/search-data.json")
      .then((response) => {
        if (!response.ok) {
          throw new Error("Failed to load search data");
        }
        return response.json();
      })
      .then((data) => {
        // Store search data in a unique namespace
        window.searchNamespace.data = data;

        searchInput.addEventListener("input", function () {
          const searchTerm = this.value.toLowerCase().trim();

          if (searchTerm.length < 2) {
            searchResults.innerHTML = "";
            searchResults.style.display = "none";
            return;
          }

          const results = filterSearchResults(data, searchTerm);

          if (results.length > 0) {
            searchResults.innerHTML = results
              .map(
                (doc) => `
                          <div class="search-result-item">
                              <a href="${doc.path}">${doc.title}</a>
                          </div>
                      `,
              )
              .join("");
            searchResults.style.display = "block";
          } else {
            searchResults.innerHTML =
              '<div class="search-result-item">No results found</div>';
            searchResults.style.display = "block";
          }
        });

        // Hide results when clicking outside
        document.addEventListener("click", function (event) {
          if (
            !searchInput.contains(event.target) &&
            !searchResults.contains(event.target)
          ) {
            searchResults.style.display = "none";
          }
        });

        // Focus search when pressing slash key
        document.addEventListener("keydown", function (event) {
          if (event.key === "/" && document.activeElement !== searchInput) {
            event.preventDefault();
            searchInput.focus();
          }
        });
      })
      .catch((error) => {
        console.error("Error loading search data:", error);
        // Create fallback empty search data so search doesn't break
        // 2025-04-05: raf was an idiot and this became necessary.
        window.searchNamespace.data = [];
        searchInput.addEventListener("input", function () {
          const searchTerm = this.value.toLowerCase().trim();
          if (searchTerm.length < 2) {
            searchResults.innerHTML = "";
            searchResults.style.display = "none";
          } else {
            searchResults.innerHTML =
              '<div class="search-result-item">No results found</div>';
            searchResults.style.display = "block";
          }
        });
      });
  }

  // Mobile search functionality;
  // This detects mobile viewport and adds click behavior
  function isMobile() {
    return window.innerWidth <= 800;
  }

  if (searchInput) {
    // Add mobile search behavior
    searchInput.addEventListener("click", function (e) {
      if (isMobile()) {
        e.preventDefault();
        e.stopPropagation();
        openMobileSearch();
      }
      // On desktop, let the normal click behavior work (focus the input)
    });

    // Prevent typing on mobile (input should only open popup)
    searchInput.addEventListener("keydown", function (e) {
      if (isMobile()) {
        e.preventDefault();
        openMobileSearch();
      }
    });
  }

  // Mobile search popup functionality
  let mobileSearchPopup = document.getElementById("mobile-search-popup");
  let mobileSearchInput = document.getElementById("mobile-search-input");
  let mobileSearchResults = document.getElementById("mobile-search-results");
  const closeMobileSearchBtn = document.getElementById("close-mobile-search");

  function openMobileSearch() {
    if (mobileSearchPopup) {
      mobileSearchPopup.classList.add("active");
      // Focus the input after a small delay to ensure the popup is visible
      setTimeout(() => {
        if (mobileSearchInput) {
          mobileSearchInput.focus();
        }
      }, 100);
    }
  }

  function closeMobileSearch() {
    if (mobileSearchPopup) {
      mobileSearchPopup.classList.remove("active");
      if (mobileSearchInput) {
        mobileSearchInput.value = "";
      }
      if (mobileSearchResults) {
        mobileSearchResults.innerHTML = "";
        mobileSearchResults.style.display = "none";
      }
    }
  }

  if (closeMobileSearchBtn) {
    closeMobileSearchBtn.addEventListener("click", closeMobileSearch);
  }

  // Close mobile search when clicking outside
  document.addEventListener("click", function (event) {
    if (
      mobileSearchPopup &&
      mobileSearchPopup.classList.contains("active") &&
      !mobileSearchPopup.contains(event.target) &&
      !searchInput.contains(event.target)
    ) {
      closeMobileSearch();
    }
  });

  // Close mobile search on escape key
  document.addEventListener("keydown", function (event) {
    if (
      event.key === "Escape" &&
      mobileSearchPopup &&
      mobileSearchPopup.classList.contains("active")
    ) {
      closeMobileSearch();
    }
  });

  // Mobile search input functionality (reuse search data if available)
  if (mobileSearchInput && mobileSearchResults) {
    let mobileSearchData = null;
    function handleMobileSearchInput() {
      const searchTerm = mobileSearchInput.value.toLowerCase().trim();
      if (!mobileSearchData) return; // data not loaded yet
      if (searchTerm.length < 2) {
        mobileSearchResults.innerHTML = "";
        mobileSearchResults.style.display = "none";
        return;
      }

      const results = filterSearchResults(mobileSearchData, searchTerm);
      if (results.length > 0) {
        mobileSearchResults.innerHTML = results
          .map(
            (doc) => `
              <div class="search-result-item">
                  <a href="${doc.path}">${doc.title}</a>
              </div>
          `,
          )
          .join("");
        mobileSearchResults.style.display = "block";
      } else {
        mobileSearchResults.innerHTML =
          '<div class="search-result-item">No results found</div>';
        mobileSearchResults.style.display = "block";
      }
    }
    // Only fetch once, then reuse
    // Something something carbon footprint something.
    if (window.searchNamespace.mobileData) {
      mobileSearchData = window.searchNamespace.mobileData;
      mobileSearchInput.addEventListener("input", handleMobileSearchInput);
    } else {
      fetch("assets/search-data.json")
        .then((response) => {
          if (!response.ok) {
            throw new Error("Failed to load search data");
          }
          return response.json();
        })
        .then((data) => {
          window.searchNamespace.mobileData = data;
          mobileSearchData = data;
          mobileSearchInput.addEventListener("input", handleMobileSearchInput);
        })
        .catch((error) => {
          console.error("Error loading search data for mobile:", error);
          mobileSearchInput.addEventListener("input", function () {
            const searchTerm = this.value.toLowerCase().trim();
            if (searchTerm.length < 2) {
              mobileSearchResults.innerHTML = "";
              mobileSearchResults.style.display = "none";
            } else {
              mobileSearchResults.innerHTML =
                '<div class="search-result-item">No results found</div>';
              mobileSearchResults.style.display = "block";
            }
          });
        });
    }
  }

  // Handle window resize to update mobile behavior
  window.addEventListener("resize", function () {
    // Close mobile search if window is resized to desktop size
    if (
      !isMobile() &&
      mobileSearchPopup &&
      mobileSearchPopup.classList.contains("active")
    ) {
      closeMobileSearch();
    }
  });
});

function performSearch(query) {
  query = query.toLowerCase().trim();
  const resultsContainer = document.getElementById("search-page-results");

  if (query.length < 2) {
    resultsContainer.innerHTML =
      "<p>Please enter at least 2 characters to search</p>";
    return;
  }

  // Search logic
  const results = window.searchNamespace.data
    .map((doc) => {
      const titleMatch = doc.title.toLowerCase().indexOf(query);
      const descMatch = doc.content.toLowerCase().indexOf(query);
      let priority = -1;
      if (titleMatch !== -1) {
        priority = 1; // title match
      } else if (descMatch !== -1) {
        priority = 2; // description match
      }
      return { doc, priority, titleMatch, descMatch };
    })
    .filter((item) => item.priority !== -1)
    .sort((a, b) => {
      if (a.priority !== b.priority) return a.priority - b.priority;
      if (a.priority === 1 && b.priority === 1)
        return a.titleMatch - b.titleMatch;
      if (a.priority === 2 && b.priority === 2)
        return a.descMatch - b.descMatch;
      return 0;
    })
    .map((item) => item.doc);

  // Display results
  if (results.length > 0) {
    let html = '<ul class="search-results-list">';
    for (const result of results) {
      const preview = generatePreview(result.content, query);
      html += `<li class="search-result-item">
        <a href="${result.path}">
          <div class="search-result-title">${result.title}</div>
          <div class="search-result-preview">${preview}</div>
        </a>
      </li>`;
    }
    html += "</ul>";
    resultsContainer.innerHTML = html;
  } else {
    resultsContainer.innerHTML = "<p>No results found</p>";
  }

  // Update URL with query
  const url = new URL(window.location.href);
  url.searchParams.set("q", query);
  window.history.replaceState({}, "", url.toString());
}

function generatePreview(content, query) {
  const maxLength = 150;
  const lowerContent = content.toLowerCase();
  const index = lowerContent.indexOf(query);

  if (index === -1) return content.slice(0, maxLength) + "...";

  const start = Math.max(0, index - 50);
  const end = Math.min(content.length, index + query.length + 50);
  let preview = content.slice(start, end);

  if (start > 0) preview = "..." + preview;
  if (end < content.length) preview += "...";

  return preview;
}
