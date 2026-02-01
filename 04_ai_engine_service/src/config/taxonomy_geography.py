"""
Hierarchical Taxonomy for Geography
- 11 base branches (major geographic domains)
- 68 detailed branches (specific topics)

Designed for both US and Chinese curricula
"""

GEOGRAPHY_BASE_BRANCHES = [
    "Map Skills & Geographic Tools",
    "Physical Geography - Landforms",
    "Physical Geography - Climate & Weather",
    "Physical Geography - Water Systems",
    "Human Geography - Population",
    "Human Geography - Culture & Society",
    "Human Geography - Economic",
    "Political Geography",
    "Regional Geography - Continents",
    "Environmental Geography",
    "Geographic Information Systems"
]

GEOGRAPHY_DETAILED_BRANCHES = {
    "Map Skills & Geographic Tools": [
        "Map Reading & Interpretation",
        "Latitude & Longitude",
        "Map Scale & Distance",
        "Map Projections",
        "Compass & Direction",
        "Topographic Maps",
        "Thematic Maps"
    ],
    "Physical Geography - Landforms": [
        "Plate Tectonics",
        "Mountains & Valleys",
        "Plains & Plateaus",
        "Coastal Features",
        "Erosion & Weathering",
        "Glaciers & Ice Features",
        "Deserts & Dunes"
    ],
    "Physical Geography - Climate & Weather": [
        "Climate Zones & Regions",
        "Temperature & Precipitation Patterns",
        "Wind & Air Circulation",
        "Climate Change & Global Warming",
        "Natural Disasters",
        "Seasons & Solar Energy"
    ],
    "Physical Geography - Water Systems": [
        "Oceans & Seas",
        "Rivers & Lakes",
        "Watersheds & Drainage Basins",
        "Groundwater & Aquifers",
        "Water Cycle",
        "Coastal Processes"
    ],
    "Human Geography - Population": [
        "Population Distribution & Density",
        "Population Growth & Demographics",
        "Migration Patterns",
        "Urbanization",
        "Rural vs Urban",
        "Population Pyramids"
    ],
    "Human Geography - Culture & Society": [
        "Cultural Regions & Diffusion",
        "Language Geography",
        "Religion & Belief Systems",
        "Ethnicity & Identity",
        "Cultural Landscapes",
        "Food & Agriculture Culture"
    ],
    "Human Geography - Economic": [
        "Economic Systems & Development",
        "Agriculture & Farming",
        "Industry & Manufacturing",
        "Trade & Globalization",
        "Natural Resources",
        "Economic Inequality"
    ],
    "Political Geography": [
        "Countries & Borders",
        "Political Systems",
        "Geopolitical Conflicts",
        "International Relations",
        "Sovereignty & Territory"
    ],
    "Regional Geography - Continents": [
        "North America",
        "South America",
        "Europe",
        "Africa",
        "Asia",
        "Oceania",
        "Antarctica & Polar Regions"
    ],
    "Environmental Geography": [
        "Ecosystems & Biomes",
        "Biodiversity & Conservation",
        "Deforestation & Land Use",
        "Pollution & Waste",
        "Sustainable Development",
        "Environmental Hazards"
    ],
    "Geographic Information Systems": [
        "GIS Technology & Mapping",
        "Spatial Analysis",
        "Remote Sensing",
        "GPS & Location Technology"
    ]
}

def get_detailed_branches_for_base(base_branch: str) -> list:
    """Get list of detailed branches for a given base branch"""
    return GEOGRAPHY_DETAILED_BRANCHES.get(base_branch, [])

def validate_taxonomy_path(base_branch: str, detailed_branch: str) -> bool:
    """Validate that detailed branch belongs to base branch"""
    return detailed_branch in GEOGRAPHY_DETAILED_BRANCHES.get(base_branch, [])
