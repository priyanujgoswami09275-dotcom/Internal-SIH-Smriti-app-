"""NER-Themed Content Packs & Match-It Board Generator.

Seedable content packs featuring North Eastern Region cultural, botanical,
wildlife, and household items. Designed for easy extension by caregivers/admins.
"""
from dataclasses import dataclass
from typing import List, Dict, Any, Optional
import random

from app.services.level_config_service import default_params


@dataclass
class ContentItem:
    id: str
    name_en: str
    name_as: str  # Assamese
    name_bn: str  # Bengali
    name_hi: str  # Hindi
    category: str
    image_url: str


@dataclass
class ContentPack:
    id: str
    name: str
    region: str
    description: str
    items: List[ContentItem]


# Seedable NER Content Packs
NER_CONTENT_PACKS: Dict[str, ContentPack] = {
    "festivals_ner": ContentPack(
        id="festivals_ner",
        name="NER Festivals & Celebrations",
        region="North East India",
        description="Traditional festivals across the 8 northeastern states.",
        items=[
            ContentItem("bihu", "Rongali Bihu", "ৰঙালী বিহু", "রঙালি বিহু", "रोंगाली बिहू", "Assam", "assets/images/match_it/festivals/bihu.png"),
            ContentItem("hornbill", "Hornbill Festival", "হৰ্ণবিল মহোৎসৱ", "হর্নবিল উৎসব", "हॉर्नबिल महोत्सव", "Nagaland", "assets/images/match_it/festivals/hornbill.png"),
            ContentItem("chapchar_kut", "Chapchar Kut", "চাপচাৰ কুট", "চাপচার কুট", "चापचार कुट", "Mizoram", "assets/images/match_it/festivals/chapchar_kut.png"),
            ContentItem("nongkrem", "Nongkrem Dance", "নংক্রেম নৃত্য", "নংক্রেম নাচ", "नोंगक्रेम नृत्य", "Meghalaya", "assets/images/match_it/festivals/nongkrem.png"),
            ContentItem("losar", "Losar", "লোচাৰ", "লোসার", "लोसार", "Arunachal Pradesh", "assets/images/match_it/festivals/losar.png"),
            ContentItem("sangken", "Sangken Water Festival", "চাংকেন", "সাংকেন", "सांगकेन", "Arunachal Pradesh", "assets/images/match_it/festivals/sangken.png"),
            ContentItem("wangala", "Wangala 100 Drums", "ৱাংগালা", "ওয়াঙ্গালা", "वांगला", "Meghalaya", "assets/images/match_it/festivals/wangala.png"),
            ContentItem("moatsu", "Moatsu Festival", "মোৱাতচু", "মোয়াতসু", "मोआत्सु", "Nagaland", "assets/images/match_it/festivals/moatsu.png"),
            ContentItem("dree", "Dree Festival", "ড্ৰী উৎসৱ", "ড্রী উৎসব", "द्री उत्सव", "Arunachal Pradesh", "assets/images/match_it/festivals/dree.png"),
            ContentItem("ningol_chakouba", "Ningol Chakouba", "নিঙল চাকৌবা", "নিঙল চাকোউবা", "निंगोल चाकोउबा", "Manipur", "assets/images/match_it/festivals/ningol_chakouba.png"),
        ],
    ),
    "fruits_flora_ner": ContentPack(
        id="fruits_flora_ner",
        name="NER Fruits & Flora",
        region="North East India",
        description="Indigenous fruits and plants familiar to NER elders.",
        items=[
            ContentItem("kaji_nemu", "Kaji Nemu (Assam Lemon)", "কাজী নেমু", "কাজী লেবু", "काजी नेमु", "Assam", "assets/images/match_it/fruits/kaji_nemu.png"),
            ContentItem("bhut_jolokia", "Bhut Jolokia (Ghost Pepper)", "ভূত জলকীয়া", "ভূত লঙ্কা", "भूत जोलोकिया", "Assam / Nagaland", "assets/images/match_it/fruits/bhut_jolokia.png"),
            ContentItem("ou_tenga", "Ou Tenga (Elephant Apple)", "ঔ টেঙা", "চালতা", "ओउ तेंगा", "Assam", "assets/images/match_it/fruits/ou_tenga.png"),
            ContentItem("jolpai", "Jolpai (Indian Olive)", "জলফাই", "জলপাই", "जलपाई", "Assam / Meghalaya", "assets/images/match_it/fruits/jolpai.png"),
            ContentItem("bamboo_shoot", "Khorisa / Bamboo Shoot", "বাঁহ গাজ / খৰিচা", "বাঁশের কোড়ল", "बांस का कोपल", "All NER", "assets/images/match_it/fruits/bamboo_shoot.png"),
            ContentItem("lakadong_turmeric", "Lakadong Turmeric", "লাকাডং হালধি", "লাকাডং হলুদ", "लकाडोंग हल्दी", "Meghalaya", "assets/images/match_it/fruits/lakadong_turmeric.png"),
            ContentItem("starfruit", "Kordoi (Starfruit)", "কৰ্দৈ", "কামরাঙা", "कमरक", "Assam", "assets/images/match_it/fruits/starfruit.png"),
            ContentItem("tamul_pan", "Tamul-Paan (Betel Nut)", "তামোল-পাণ", "সুপারি-পান", "तामुल-पान", "All NER", "assets/images/match_it/fruits/tamul_pan.png"),
            ContentItem("kopou_phool", "Kopou Phool (Foxtail Orchid)", "কপৌ ফুল", "কপৌ ফুল", "कोपौ फूल", "Assam / Arunachal", "assets/images/match_it/fruits/kopou_phool.png"),
            ContentItem("assam_tea_leaf", "Assam Tea Leaf", "চাহ পাত", "অসম চা পাতা", "असम चाय पत्ती", "Assam", "assets/images/match_it/fruits/assam_tea_leaf.png"),
        ],
    ),
    "heritage_household_ner": ContentPack(
        id="heritage_household_ner",
        name="Heritage & Household Objects",
        region="North East India",
        description="Everyday traditional items and symbols of the North East.",
        items=[
            ContentItem("jaapi", "Jaapi (Traditional Hat)", "জাপি", "জাপি", "जापी", "Assam", "assets/images/match_it/heritage/jaapi.png"),
            ContentItem("xorai", "Xorai (Bell Metal Tray)", "শৰাই", "শরাই", "शराई", "Assam", "assets/images/match_it/heritage/xorai.png"),
            ContentItem("gamosa", "Gamosa (Handwoven Towel)", "গামোচা", "গামোছা", "गमोसा", "Assam", "assets/images/match_it/heritage/gamosa.png"),
            ContentItem("rhino", "One-Horned Rhino", "এশিঙীয়া গঁড়", "একশৃঙ্গ গণ্ডার", "एक सींग वाला गैंडा", "Assam (Kaziranga)", "assets/images/match_it/heritage/rhino.png"),
            ContentItem("red_panda", "Red Panda", "ৰেড পাণ্ডা", "রেড পান্ডা", "लाल पांडा", "Sikkim / Arunachal", "assets/images/match_it/heritage/red_panda.png"),
            ContentItem("dhol", "Assamese Bihu Dhol", "বিহু ঢোল", "ঢোল", "बिहू ढोल", "Assam", "assets/images/match_it/heritage/dhol.png"),
            ContentItem("pepa", "Pepa (Buffalo Horn Flute)", "পেঁপা", "পেঁপা", "पेंपा", "Assam", "assets/images/match_it/heritage/pepa.png"),
            ContentItem("mekhela_sador", "Mekhela Sador", "মেখেলা চাদৰ", "মেখেলা চাদর", "मेखेला सादोर", "Assam", "assets/images/match_it/heritage/mekhela_sador.png"),
            ContentItem("puan", "Mizo Puan (Traditional Attire)", "পুৱান", "পুয়ান", "पुआन", "Mizoram", "assets/images/match_it/heritage/puan.png"),
            ContentItem("eri_silk", "Eri Silk (Ahimsa Silk)", "এৰি পাট", "এরি রেশম", "एरी रेशम", "Assam", "assets/images/match_it/heritage/eri_silk.png"),
            ContentItem("bamboo_craft", "Bamboo Craft", "বাঁহৰ শিল্প", "বাঁশের হস্তশিল্প", "बांस शिल्प", "All NER", "assets/images/match_it/heritage/bamboo_craft.png"),
            ContentItem("naga_shawl", "Naga Shawl", "নাগা চাদৰ", "নাগা শাল", "नागा शॉल", "Nagaland", "assets/images/match_it/heritage/naga_shawl.png"),
        ],
    ),
}

# Pair counts resolve from game_level_config (DEFAULT_LEVEL_CONFIG fallback).
# Do not reintroduce a local map — the table is the single source of truth.
def _pairs_for_level(difficulty_level: int) -> int:
    return default_params("match_it", difficulty_level).get("pairs", 2)


def register_content_pack(
    pack_id: str,
    name: str,
    region: str,
    description: str,
    items: List[Dict[str, Any]],
) -> ContentPack:
    """Register (or replace) a themed set so caregivers/admins can add packs without a deploy."""
    pack = ContentPack(
        id=pack_id,
        name=name,
        region=region,
        description=description,
        items=[
            ContentItem(
                id=str(item.get("id")),
                name_en=item.get("name_en", ""),
                name_as=item.get("name_as", ""),
                name_bn=item.get("name_bn", ""),
                name_hi=item.get("name_hi", ""),
                category=item.get("category", ""),
                image_url=item.get("image_url", ""),
            )
            for item in items
        ],
    )
    NER_CONTENT_PACKS[pack_id] = pack
    return pack


def list_content_packs() -> List[Dict[str, Any]]:
    """Return summary metadata for all registered content packs."""
    return [
        {
            "id": pack.id,
            "name": pack.name,
            "region": pack.region,
            "description": pack.description,
            "item_count": len(pack.items),
        }
        for pack in NER_CONTENT_PACKS.values()
    ]


def generate_match_it_board(
    pack_id: str = "festivals_ner",
    difficulty_level: int = 1,
    pair_count: Optional[int] = None,
) -> Dict[str, Any]:
    """Generate a randomized match-it board configuration for a given pack and difficulty.

    pair_count resolves from game_level_config when omitted (routes pass the
    DB-resolved value); the parameter exists so offline/pure callers stay sync.
    """
    pack = NER_CONTENT_PACKS.get(pack_id) or NER_CONTENT_PACKS["festivals_ner"]
    if not pack.items:
        raise ValueError(f"Content pack '{pack.id}' has no playable items")
    if pair_count is None:
        pair_count = _pairs_for_level(difficulty_level)
    pair_count = max(1, min(pair_count, len(pack.items)))

    # Pick N random distinct items from pack
    selected_items = random.sample(pack.items, pair_count)

    cards = []
    card_id = 1
    for item in selected_items:
        # 2 cards per item
        for pair_index in [1, 2]:
            cards.append({
                "card_id": card_id,
                "item_id": item.id,
                "name_en": item.name_en,
                "name_as": item.name_as,
                "name_bn": item.name_bn,
                "name_hi": item.name_hi,
                "image_url": item.image_url,
                "matched": False,
            })
            card_id += 1

    random.shuffle(cards)

    return {
        "pack_id": pack.id,
        "pack_name": pack.name,
        "difficulty_level": difficulty_level,
        "pair_count": pair_count,
        "total_cards": len(cards),
        "cards": cards,
    }
