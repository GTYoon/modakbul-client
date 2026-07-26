import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;

public final class GenerateModakbulMenus {
    // FancyMenu temporarily normalizes these layouts to a 640x336 logical canvas.
    // This keeps the same proportions at Minecraft GUI scales 1 through 5 while
    // leaving only a small outer margin around the 607x310 main panel.
    private static final int RESPONSIVE_BASE_WIDTH = 640;
    private static final int RESPONSIVE_BASE_HEIGHT = 336;
    private static final double HORIZONTAL_LAYOUT_SCALE = 0.74;
    private static final double VERTICAL_LAYOUT_SCALE = 0.68;
    private static final double TEXT_LAYOUT_SCALE = 0.72;
    private static final int VERTICAL_LAYOUT_OFFSET = 6;
    private static final String ASSET_ROOT = "[source:local]/config/fancymenu/assets/";
    private static final String NORMAL_BUTTON = ASSET_ROOT + "ui_button.png";
    private static final String HOVER_BUTTON = ASSET_ROOT + "ui_button_hover.png";
    private static final String INACTIVE_BUTTON = ASSET_ROOT + "ui_button_inactive.png";
    private static final String PANEL = ASSET_ROOT + "ui_panel.png";
    private static final String SOFT_PANEL = ASSET_ROOT + "ui_panel_soft.png";

    private record Action(String type, String value) {
    }

    private GenerateModakbulMenus() {
    }

    public static void main(String[] args) throws Exception {
        if (args.length != 1) {
            throw new IllegalArgumentException("Usage: GenerateModakbulMenus <fancymenu-config-directory>");
        }

        Path configDirectory = Path.of(args[0]).toAbsolutePath().normalize();
        Path customizationDirectory = configDirectory.resolve("customization");
        Files.createDirectories(customizationDirectory);

        write(customizationDirectory.resolve("cobbleverse_pause_menu.txt"), pauseMenu());
        write(customizationDirectory.resolve("modakbul_region_travel.txt"), regionTravelMenu());
        write(customizationDirectory.resolve("modakbul_quick_guide.txt"), quickGuideMenu());
        write(configDirectory.resolve("custom_gui_screens.txt"), customGuiScreens());
    }

    private static String pauseMenu() {
        StringBuilder out = new StringBuilder(layoutHeader("pause_screen"));

        out.append(panel("pause-outer-panel", PANEL, -410, 12, 820, 456));
        out.append(panel("pause-header-panel", SOFT_PANEL, -390, 26, 780, 52));
        out.append(panel("pause-navigation-panel", SOFT_PANEL, -390, 90, 170, 324));
        out.append(panel("pause-content-panel", SOFT_PANEL, -208, 90, 598, 324));
        out.append(panel("pause-location-info-panel", PANEL, -190, 218, 272, 158));
        out.append(panel("pause-server-info-panel", PANEL, 96, 218, 276, 158));
        out.append(panel("pause-footer-panel", SOFT_PANEL, -390, 422, 780, 34));

        out.append(image("pause-logo", "icon_pokemon.png", -370, 34, 36, 36, false));
        out.append(text("pause-title", "&f&l모닥불 Season 1", -326, 35, 310, 20, 1.35, "#FFFFFFFF"));
        out.append(text("pause-subtitle", "&7포켓몬과 함께 쉬어가는 우리들의 서버", -326, 58, 360, 14, 1.02, "#D7E7FFFF"));

        out.append(text("pause-navigation-title", "&b&l메인 메뉴", -370, 105, 140, 16, 1.0, "#FFFFFFFF"));
        out.append(button(
            "pause-guide", "&f이용 안내", -372, 130, 134, 32,
            new Action("opengui", "modakbul_quick_guide")
        ));
        out.append(image("pause-guide-icon", "icon_pokemon.png", -362, 136, 20, 20, false));
        out.append(button(
            "pause-region", "&f지역 이동", -372, 170, 134, 32,
            new Action("opengui", "modakbul_region_travel")
        ));
        out.append(image("pause-region-icon", "icon_compass.png", -362, 176, 20, 20, false));

        out.append(button(
            "pause-settings", "&f설정", -372, 210, 134, 32,
            new Action("opengui", "options_screen")
        ));
        out.append(image("pause-settings-icon", "icon_settings.png", -362, 216, 20, 20, false));
        out.append(text("pause-navigation-tip-one", "&7ESC로 언제든 다시 열기", -368, 266, 142, 13, 1.0, "#C8D6E8FF"));
        out.append(text("pause-navigation-tip-two", "&7이동 · 안내 · 설정을 한곳에서", -368, 282, 145, 13, 0.96, "#C8D6E8FF"));

        out.append(text("pause-quick-title", "&f&l빠른 이동", -190, 106, 100, 17, 1.05, "#FFFFFFFF"));
        out.append(text("pause-quick-subtitle", "&7원하는 장소를 바로 선택하세요.", -80, 108, 250, 14, 1.0, "#C8D6E8FF"));
        out.append(button(
            "pause-spawn", "&f&l마을", -190, 135, 170, 62,
            new Action("sendmessage", "/spawn"),
            new Action("closegui", "")
        ));
        out.append(image("pause-spawn-icon", "icon_village.png", -176, 149, 34, 34, false));
        out.append(button(
            "pause-wild", "&f&l야생", -2, 135, 170, 62,
            new Action("sendmessage", "/야생"),
            new Action("closegui", "")
        ));
        out.append(image("pause-wild-icon", "icon_compass.png", 12, 149, 34, 34, false));
        out.append(button(
            "pause-home", "&f&l내 홈", 186, 135, 170, 62,
            new Action("sendmessage", "/home"),
            new Action("closegui", "")
        ));
        out.append(image("pause-home-icon", "icon_home.png", 200, 149, 34, 34, false));

        out.append(text("pause-location-title", "&b&l지역 이동", -174, 234, 220, 16, 0.98, "#FFFFFFFF"));
        out.append(text("pause-location-one", "&f마을1 · 마을2 · 마을3", -174, 258, 230, 14, 1.0, "#E8F2FFFF"));
        out.append(text("pause-location-two", "&f경기장 · 상점가 · 도박장", -174, 279, 240, 14, 1.0, "#E8F2FFFF"));
        out.append(text("pause-location-three", "&7세부 목적지는 지역 이동에서", -174, 309, 240, 14, 0.96, "#C1CEE0FF"));
        out.append(text("pause-location-four", "&7선택할 수 있습니다.", -174, 326, 220, 14, 0.96, "#C1CEE0FF"));

        out.append(text("pause-server-title", "&d&l이용 안내", 112, 234, 220, 16, 0.98, "#FFFFFFFF"));
        out.append(text("pause-server-one", "&f야생: 마지막 야생 위치로 이동", 112, 258, 245, 14, 1.0, "#E8F2FFFF"));
        out.append(text("pause-server-two", "&fPC: 마을의 PC 블록 이용", 112, 279, 245, 14, 1.0, "#E8F2FFFF"));
        out.append(text("pause-server-three", "&f건축: 건차 허용 구역에서만", 112, 300, 245, 14, 1.0, "#E8F2FFFF"));
        out.append(text("pause-server-four", "&7자세한 내용은 왼쪽 안내 메뉴", 112, 330, 245, 14, 0.96, "#C1CEE0FF"));

        out.append(button(
            "pause-resume", "&f게임으로 돌아가기", 242, 39, 126, 28,
            new Action("closegui", "")
        ));
        out.append(button(
            "pause-disconnect", "&c서버 나가기", -372, 425, 134, 26,
            new Action("disconnect_server_or_world", "join_multiplayer_screen")
        ));
        out.append(image("pause-exit-icon", "icon_exit.png", -361, 428, 20, 20, false));
        out.append(text(
            "pause-footer-message", "&7모닥불 Season 1 · 편안한 모험 되세요.",
            -214, 431, 420, 13, 0.98, "#AEBED3FF"
        ));
        out.append(hiddenVanilla("pause_options_button"));
        out.append(hiddenVanilla("pause_return_to_game_button"));
        out.append(hiddenVanilla("pause_disconnect_button"));
        out.append(hiddenVanilla("pause_advancements_button"));
        out.append(hiddenVanilla("pause_share_to_lan_button"));
        out.append(hiddenVanilla("pause_report_bugs_button"));
        out.append(hiddenVanilla("pause_send_feedback_button"));
        out.append(hiddenVanilla("pause_stats_button"));
        out.append(hiddenVanilla("606306"));
        out.append(hiddenVanilla("40"));

        return out.toString();
    }

    private static String regionTravelMenu() {
        StringBuilder out = new StringBuilder(layoutHeader("modakbul_region_travel"));

        out.append(panel("region-outer-panel", PANEL, -410, 12, 820, 456));
        out.append(panel("region-header-panel", SOFT_PANEL, -390, 26, 780, 54));
        out.append(panel("region-fast-panel", SOFT_PANEL, -390, 92, 780, 96));
        out.append(panel("region-village-panel", SOFT_PANEL, -390, 198, 780, 96));
        out.append(panel("region-facility-panel", SOFT_PANEL, -390, 304, 780, 96));
        out.append(panel("region-note-panel", SOFT_PANEL, -250, 410, 640, 40));

        out.append(image("region-logo", "icon_compass.png", -370, 34, 38, 38, false));
        out.append(text("region-title", "&f&l지역 이동", -322, 34, 240, 20, 1.4, "#FFFFFFFF"));
        out.append(text("region-subtitle", "&7목적지를 누르면 해당 장소로 바로 이동합니다.", -322, 59, 390, 14, 0.82, "#D7E7FFFF"));

        out.append(text("region-fast-title", "&b&l빠른 이동", -370, 102, 140, 16, 0.95, "#FFFFFFFF"));
        out.append(button(
            "region-spawn", "&f&l마을  &7/spawn", -350, 126, 210, 48,
            new Action("sendmessage", "/spawn"),
            new Action("closegui", "")
        ));
        out.append(image("region-spawn-icon", "icon_village.png", -336, 136, 28, 28, false));
        out.append(button(
            "region-wild", "&f&l야생  &7/야생", -105, 126, 210, 48,
            new Action("sendmessage", "/야생"),
            new Action("closegui", "")
        ));
        out.append(image("region-wild-icon", "icon_compass.png", -91, 136, 28, 28, false));
        out.append(button(
            "region-home", "&f&l내 홈  &7/home", 140, 126, 210, 48,
            new Action("sendmessage", "/home"),
            new Action("closegui", "")
        ));
        out.append(image("region-home-icon", "icon_home.png", 154, 136, 28, 28, false));

        out.append(text("region-village-title", "&b&l마을", -370, 208, 140, 16, 0.95, "#FFFFFFFF"));
        out.append(button(
            "region-village-one", "&f&l마을1", -350, 232, 210, 48,
            new Action("sendmessage", "/마을1"),
            new Action("closegui", "")
        ));
        out.append(image("region-village-one-icon", "icon_village.png", -336, 242, 28, 28, false));
        out.append(button(
            "region-village-two", "&f&l마을2", -105, 232, 210, 48,
            new Action("sendmessage", "/마을2"),
            new Action("closegui", "")
        ));
        out.append(image("region-village-two-icon", "icon_village.png", -91, 242, 28, 28, false));
        out.append(button(
            "region-village-three", "&f&l마을3", 140, 232, 210, 48,
            new Action("sendmessage", "/마을3"),
            new Action("closegui", "")
        ));
        out.append(image("region-village-three-icon", "icon_village.png", 154, 242, 28, 28, false));

        out.append(text("region-facility-title", "&d&l주요 시설", -370, 314, 140, 16, 0.95, "#FFFFFFFF"));
        out.append(button(
            "region-arena", "&f&l경기장", -350, 338, 210, 48,
            new Action("sendmessage", "/경기장"),
            new Action("closegui", "")
        ));
        out.append(image("region-arena-icon", "icon_arena.png", -336, 348, 28, 28, false));
        out.append(button(
            "region-market", "&f&l상점가", -105, 338, 210, 48,
            new Action("sendmessage", "/상점가"),
            new Action("closegui", "")
        ));
        out.append(image("region-market-icon", "icon_market.png", -91, 348, 28, 28, false));
        out.append(button(
            "region-casino", "&f&l도박장", 140, 338, 210, 48,
            new Action("sendmessage", "/도박장"),
            new Action("closegui", "")
        ));
        out.append(image("region-casino-icon", "icon_casino.png", 154, 348, 28, 28, false));

        out.append(button(
            "region-back", "&f이전 화면", -390, 416, 124, 28,
            new Action("back_to_last_screen", "")
        ));
        out.append(text("region-note-one", "&7야생은 마지막으로 머물렀던 야생 좌표로 이동합니다.", -232, 420, 590, 13, 0.84, "#C8D6E8FF"));
        out.append(text("region-note-two", "&7마을 슬롯의 표시 이름을 바꿔도 /마을1~3 명령은 유지됩니다.", -232, 436, 590, 13, 0.78, "#AEBED3FF"));

        return out.toString();
    }

    private static String quickGuideMenu() {
        StringBuilder out = new StringBuilder(layoutHeader("modakbul_quick_guide"));

        out.append(panel("guide-outer-panel", PANEL, -410, 12, 820, 456));
        out.append(panel("guide-header-panel", SOFT_PANEL, -390, 26, 780, 54));
        out.append(panel("guide-town-panel", SOFT_PANEL, -390, 94, 380, 142));
        out.append(panel("guide-wild-panel", SOFT_PANEL, 10, 94, 380, 142));
        out.append(panel("guide-pc-panel", SOFT_PANEL, -390, 250, 380, 142));
        out.append(panel("guide-building-panel", SOFT_PANEL, 10, 250, 380, 142));
        out.append(panel("guide-footer-panel", SOFT_PANEL, -250, 406, 640, 44));

        out.append(image("guide-logo", "icon_pokemon.png", -370, 34, 38, 38, false));
        out.append(text("guide-title", "&f&l모닥불 이용 안내", -322, 34, 300, 20, 1.38, "#FFFFFFFF"));
        out.append(text("guide-subtitle", "&7처음 접속했다면 아래 네 가지만 기억하세요.", -322, 59, 390, 14, 0.82, "#D7E7FFFF"));

        out.append(image("guide-town-icon", "icon_village.png", -370, 112, 42, 42, false));
        out.append(text("guide-town-title", "&b&l마을", -316, 108, 250, 18, 1.08, "#FFFFFFFF"));
        out.append(text("guide-town-one", "&f- 상점 · 경기장 · 도박장 이용", -316, 138, 270, 14, 0.82, "#E8F2FFFF"));
        out.append(text("guide-town-two", "&f- 야생 포켓몬 자연 스폰 없음", -316, 161, 270, 14, 0.82, "#E8F2FFFF"));
        out.append(text("guide-town-three", "&f- 꿀벌 생산과 목장 블록은 이용 가능", -316, 184, 290, 14, 0.78, "#E8F2FFFF"));

        out.append(image("guide-wild-icon", "icon_compass.png", 30, 112, 42, 42, false));
        out.append(text("guide-wild-title", "&b&l야생", 84, 108, 250, 18, 1.08, "#FFFFFFFF"));
        out.append(text("guide-wild-one", "&f- 포켓몬 포획과 자원 탐험 공간", 84, 138, 270, 14, 0.82, "#E8F2FFFF"));
        out.append(text("guide-wild-two", "&f- /야생으로 마지막 야생 위치 복귀", 84, 161, 280, 14, 0.80, "#E8F2FFFF"));
        out.append(text("guide-wild-three", "&f- 이동 전 전투와 탑승을 마무리", 84, 184, 270, 14, 0.80, "#E8F2FFFF"));

        out.append(image("guide-pc-icon", "icon_pokemon.png", -370, 268, 42, 42, false));
        out.append(text("guide-pc-title", "&d&l포켓몬 PC", -316, 264, 250, 18, 1.08, "#FFFFFFFF"));
        out.append(text("guide-pc-one", "&f- P키 원격 PC는 비활성화", -316, 294, 270, 14, 0.82, "#E8F2FFFF"));
        out.append(text("guide-pc-two", "&f- 마을의 PC 블록에서 보관함 이용", -316, 317, 280, 14, 0.80, "#E8F2FFFF"));
        out.append(text("guide-pc-three", "&7- 마을 시설을 적극 이용해주세요.", -316, 340, 270, 14, 0.78, "#C1CEE0FF"));

        out.append(image("guide-building-icon", "icon_home.png", 30, 268, 42, 42, false));
        out.append(text("guide-building-title", "&d&l건축", 84, 264, 250, 18, 1.08, "#FFFFFFFF"));
        out.append(text("guide-building-one", "&f- 마을에서는 건차 블록만 설치 가능", 84, 294, 280, 14, 0.78, "#E8F2FFFF"));
        out.append(text("guide-building-two", "&f- 건차가 만든 구역 안에서만 건축", 84, 317, 280, 14, 0.80, "#E8F2FFFF"));
        out.append(text("guide-building-three", "&f- 다른 월드에서는 건차 사용 불가", 84, 340, 270, 14, 0.80, "#E8F2FFFF"));

        out.append(button(
            "guide-back", "&f이전 화면", -390, 414, 124, 28,
            new Action("back_to_last_screen", "")
        ));
        out.append(button(
            "guide-region", "&f지역 이동 열기", 242, 414, 126, 28,
            new Action("opengui", "modakbul_region_travel")
        ));
        out.append(text("guide-footer-tip", "&7ESC → 지역 이동에서 모든 목적지를 확인할 수 있습니다.", -232, 420, 450, 13, 0.86, "#C8D6E8FF"));

        return out.toString();
    }

    private static String customGuiScreens() {
        return """
            type = custom_gui_screens

            overridden_screens {
            }

            custom_gui {
              identifier = welcomescreen_update
              title = What's New?
              allow_esc = true
              transparent_world_background = true
              transparent_world_background_overlay = false
              pause_game = true
            }

            custom_gui {
              identifier = welcomescreen_welcome
              title =
              allow_esc = true
              transparent_world_background = true
              transparent_world_background_overlay = false
              pause_game = true
            }

            custom_gui {
              identifier = modakbul_region_travel
              title =
              allow_esc = true
              transparent_world_background = true
              transparent_world_background_overlay = true
              pause_game = true
            }

            custom_gui {
              identifier = modakbul_quick_guide
              title =
              allow_esc = true
              transparent_world_background = true
              transparent_world_background_overlay = true
              pause_game = true
            }
            """;
    }

    private static String layoutHeader(String identifier) {
        return """
            type = fancymenu_layout

            layout-meta {
              identifier = %s
              render_custom_elements_behind_vanilla = false
              last_edited_time = 1785037200000
              is_enabled = true
              randommode = false
              randomgroup = 1
              randomonlyfirsttime = false
              layout_index = 0
              [loading_requirement_container_meta:%s-layout-load] = [groups:][instances:]
            }

            customization {
              action = setscale
              scale = 1.0
            }

            customization {
              action = autoscale
              basewidth = %d
              baseheight = %d
            }

            customization {
              action = backgroundoptions
              keepaspectratio = false
            }

            scroll_list_customization {
              preserve_scroll_list_header_footer_aspect_ratio = true
              render_scroll_list_header_shadow = true
              render_scroll_list_footer_shadow = true
              show_scroll_list_header_footer_preview_in_editor = false
              show_screen_background_overlay_on_custom_background = true
              apply_vanilla_background_blur = true
            }

            """.formatted(
                identifier,
                identifier,
                RESPONSIVE_BASE_WIDTH,
                RESPONSIVE_BASE_HEIGHT
            );
    }

    private static String panel(String id, String source, int x, int y, int width, int height) {
        return image(id, source.substring(ASSET_ROOT.length()), x, y, width, height, true);
    }

    private static String image(
        String id,
        String file,
        int x,
        int y,
        int width,
        int height,
        boolean nineSlice
    ) {
        String source = file.startsWith("[source:") ? file : ASSET_ROOT + file;
        StringBuilder out = new StringBuilder();
        out.append("element {\n");
        out.append("  interactable = false\n");
        out.append("  source = ").append(source).append('\n');
        out.append("  repeat_texture = false\n");
        out.append("  nine_slice_texture = ").append(nineSlice).append('\n');
        out.append("  nine_slice_texture_border_x = 6\n");
        out.append("  nine_slice_texture_border_y = 6\n");
        out.append("  image_tint = #FFFFFFFF\n");
        out.append("  element_type = image\n");
        out.append("  instance_identifier = ").append(id).append('\n');
        appendCommon(out, id, "top-centered", x, y, width, height);
        out.append("}\n\n");
        return out.toString();
    }

    private static String text(
        String id,
        String content,
        int x,
        int y,
        int width,
        int height,
        double scale,
        String color
    ) {
        StringBuilder out = new StringBuilder();
        out.append("element {\n");
        out.append("  interactable = false\n");
        out.append("  source = ").append(content).append('\n');
        out.append("  source_mode = direct\n");
        out.append("  shadow = true\n");
        out.append("  scale = ").append(roundScale(scale * TEXT_LAYOUT_SCALE)).append('\n');
        out.append("  base_color = ").append(color).append('\n');
        out.append("  text_border = 0\n");
        out.append("  line_spacing = 2\n");
        out.append("  enable_scrolling = false\n");
        out.append("  auto_line_wrapping = false\n");
        out.append("  remove_html_breaks = true\n");
        out.append("  parse_markdown = false\n");
        out.append("  element_type = text_v2\n");
        out.append("  instance_identifier = ").append(id).append('\n');
        appendCommon(out, id, "top-centered", x, y, width, height);
        out.append("}\n\n");
        return out.toString();
    }

    private static String button(
        String id,
        String label,
        int x,
        int y,
        int width,
        int height,
        Action... actions
    ) {
        String blockId = id + "-block";
        List<String> actionIds = new ArrayList<>();
        StringBuilder out = new StringBuilder();
        out.append("element {\n");
        out.append("  button_element_executable_block_identifier = ").append(blockId).append('\n');
        for (int index = 0; index < actions.length; index++) {
            Action action = actions[index];
            String actionId = id + "-action-" + (index + 1);
            actionIds.add(actionId);
            out.append("  [executable_action_instance:").append(actionId)
                .append("][action_type:").append(action.type()).append("] =");
            if (!action.value().isEmpty()) {
                out.append(' ').append(action.value());
            }
            out.append('\n');
        }
        out.append("  [executable_block:").append(blockId)
            .append("][type:generic] = [executables:");
        for (String actionId : actionIds) {
            out.append(actionId).append(';');
        }
        out.append("]\n");
        appendButtonStyle(out);
        out.append("  label = ").append(label).append('\n');
        out.append("  navigatable = true\n");
        out.append("  is_template = false\n");
        out.append("  template_share_with = buttons\n");
        out.append("  element_type = custom_button\n");
        out.append("  instance_identifier = ").append(id).append('\n');
        appendCommon(out, id, "top-centered", x, y, width, height);
        out.append("}\n\n");
        return out.toString();
    }

    private static String vanillaButton(
        String id,
        String label,
        int x,
        int y,
        int width,
        int height,
        boolean hidden
    ) {
        StringBuilder out = new StringBuilder();
        out.append("vanilla_button {\n");
        appendButtonStyle(out);
        if (label != null && !label.isBlank()) {
            out.append("  label = ").append(label).append('\n');
        }
        out.append("  navigatable = true\n");
        out.append("  is_template = false\n");
        out.append("  template_share_with = buttons\n");
        out.append("  element_type = vanilla_button\n");
        out.append("  instance_identifier = ").append(id).append('\n');
        appendCommon(out, id, "top-centered", x, y, width, height);
        out.append("  is_hidden = ").append(hidden).append('\n');
        out.append("  automated_button_clicks = 0\n");
        out.append("}\n\n");
        return out.toString();
    }

    private static String hiddenVanilla(String id) {
        return vanillaButton(id, "", -500, -500, 20, 20, true);
    }

    private static void appendButtonStyle(StringBuilder out) {
        out.append("  restartbackgroundanimations = true\n");
        out.append("  backgroundnormal = ").append(NORMAL_BUTTON).append('\n');
        out.append("  backgroundhovered = ").append(HOVER_BUTTON).append('\n');
        out.append("  background_texture_inactive = ").append(INACTIVE_BUTTON).append('\n');
        out.append("  nine_slice_custom_background = true\n");
        out.append("  nine_slice_border_x = 6\n");
        out.append("  nine_slice_border_y = 6\n");
        out.append("  nine_slice_slider_handle = false\n");
        out.append("  nine_slice_slider_handle_border_x = 6\n");
        out.append("  nine_slice_slider_handle_border_y = 6\n");
    }

    private static void appendCommon(
        StringBuilder out,
        String id,
        String anchor,
        int x,
        int y,
        int width,
        int height
    ) {
        out.append("  appearance_delay = no_delay\n");
        out.append("  appearance_delay_seconds = 1.0\n");
        out.append("  fade_in_v2 = no_fading\n");
        out.append("  fade_in_speed = 1.0\n");
        out.append("  fade_out = no_fading\n");
        out.append("  fade_out_speed = 1.0\n");
        out.append("  base_opacity = 1.0\n");
        out.append("  auto_sizing = false\n");
        out.append("  auto_sizing_base_screen_width = 1920\n");
        out.append("  auto_sizing_base_screen_height = 1080\n");
        out.append("  sticky_anchor = false\n");
        out.append("  anchor_point = ").append(anchor).append('\n');
        out.append("  x = ").append(scaleCoordinate(x, HORIZONTAL_LAYOUT_SCALE)).append('\n');
        out.append("  y = ").append(scaleCoordinate(y, VERTICAL_LAYOUT_SCALE) + VERTICAL_LAYOUT_OFFSET).append('\n');
        out.append("  width = ").append(scaleSize(width, HORIZONTAL_LAYOUT_SCALE)).append('\n');
        out.append("  height = ").append(scaleSize(height, VERTICAL_LAYOUT_SCALE)).append('\n');
        out.append("  stretch_x = false\n");
        out.append("  stretch_y = false\n");
        out.append("  stay_on_screen = true\n");
        out.append("  element_loading_requirement_container_identifier = ").append(id).append("-load\n");
        out.append("  [loading_requirement_container_meta:").append(id)
            .append("-load] = [groups:][instances:]\n");
        out.append("  enable_parallax = false\n");
        out.append("  parallax_intensity = 0.5\n");
        out.append("  invert_parallax = false\n");
        out.append("  animated_offset_x = 0\n");
        out.append("  animated_offset_y = 0\n");
        out.append("  load_once_per_session = false\n");
        out.append("  in_editor_color = #45B9FFFF\n");
        out.append("  layer_hidden_in_editor = false\n");
    }

    private static int scaleCoordinate(int value, double scale) {
        return (int) Math.round(value * scale);
    }

    private static int scaleSize(int value, double scale) {
        return Math.max(1, scaleCoordinate(value, scale));
    }

    private static double roundScale(double value) {
        return Math.round(value * 1000.0) / 1000.0;
    }

    private static void write(Path path, String content) throws IOException {
        Files.writeString(
            path,
            content.replace("\r\n", "\n").stripTrailing() + "\n",
            StandardCharsets.UTF_8
        );
        System.out.println("Wrote " + path);
    }
}
