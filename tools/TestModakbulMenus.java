import java.awt.image.BufferedImage;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import javax.imageio.ImageIO;

public final class TestModakbulMenus {
    private static final Pattern INSTANCE =
        Pattern.compile("(?m)^\\s*instance_identifier\\s*=\\s*([^\\r\\n]+)$");
    private static final Pattern ASSET =
        Pattern.compile("\\[source:local\\]/config/fancymenu/assets/([^\\r\\n]+)");
    private static final Pattern ACTION =
        Pattern.compile("\\[executable_action_instance:([^]]+)]\\[action_type:([^]]+)]");
    private static final Pattern BLOCK =
        Pattern.compile("\\[executable_block:([^]]+)]\\[type:generic]\\s*=\\s*\\[executables:([^]]*)]");
    private static final Pattern BUTTON_BLOCK =
        Pattern.compile("(?m)^\\s*button_element_executable_block_identifier\\s*=\\s*([^\\r\\n]+)$");
    private static final Pattern ELEMENT_BLOCK =
        Pattern.compile("(?s)(?:element|vanilla_button)\\s*\\{(.*?)\\n}");
    private static final Pattern CUSTOMIZATION_BLOCK =
        Pattern.compile("(?ms)^customization\\s*\\{(.*?)\\n}");
    private static final int RESPONSIVE_BASE_WIDTH = 640;
    private static final int RESPONSIVE_BASE_HEIGHT = 336;

    private TestModakbulMenus() {
    }

    public static void main(String[] args) throws Exception {
        if (args.length != 1) {
            throw new IllegalArgumentException("Usage: TestModakbulMenus <fancymenu-config-directory>");
        }

        Path config = Path.of(args[0]).toAbsolutePath().normalize();
        Path customization = config.resolve("customization");
        Map<String, String> layouts = new HashMap<>();
        layouts.put("cobbleverse_pause_menu.txt", "pause_screen");
        layouts.put("modakbul_region_travel.txt", "modakbul_region_travel");
        layouts.put("modakbul_quick_guide.txt", "modakbul_quick_guide");

        for (Map.Entry<String, String> entry : layouts.entrySet()) {
            Path path = customization.resolve(entry.getKey());
            String content = Files.readString(path, StandardCharsets.UTF_8);
            require(content.contains("identifier = " + entry.getValue()), path + ": wrong layout identifier");
            require(braceBalance(content) == 0, path + ": unbalanced braces");
            require(!containsMojibake(content), path + ": Korean text contains mojibake");
            requireUniqueInstances(path, content);
            requireAssetsExist(config, path, content);
            requireActionsConnected(path, content);
            requireCustomButtonTextures(path, content);
            requireResponsiveLayout(path, content);
            requireFitsDefaultGui(
                path,
                content,
                RESPONSIVE_BASE_WIDTH,
                RESPONSIVE_BASE_HEIGHT
            );
            requireCanvasCoverage(
                path,
                content,
                RESPONSIVE_BASE_WIDTH,
                RESPONSIVE_BASE_HEIGHT
            );
        }

        String pause = Files.readString(customization.resolve("cobbleverse_pause_menu.txt"), StandardCharsets.UTF_8);
        require(count(pause, "[action_type:sendmessage] = /spawn") == 1, "pause /spawn action count");
        require(count(pause, "[action_type:sendmessage] = /야생") == 1, "pause /야생 action count");
        require(count(pause, "[action_type:sendmessage] = /home") == 1, "pause /home action count");
        require(pause.contains("[action_type:opengui] = options_screen"), "pause options action missing");
        require(pause.contains("[action_type:closegui] ="), "pause resume action missing");
        require(pause.contains("[action_type:disconnect_server_or_world] = join_multiplayer_screen"),
            "pause disconnect action missing");
        requireVanillaHidden(pause, "pause_options_button");
        requireVanillaHidden(pause, "pause_return_to_game_button");
        requireVanillaHidden(pause, "pause_disconnect_button");

        String region = Files.readString(customization.resolve("modakbul_region_travel.txt"), StandardCharsets.UTF_8);
        for (String command : List.of(
            "/spawn", "/야생", "/home", "/마을1", "/마을2", "/마을3", "/경기장", "/상점가", "/도박장"
        )) {
            require(count(region, "[action_type:sendmessage] = " + command) == 1,
                "region action count for " + command);
        }
        require(region.contains("[action_type:back_to_last_screen] ="), "region back action missing");

        String guide = Files.readString(customization.resolve("modakbul_quick_guide.txt"), StandardCharsets.UTF_8);
        require(guide.contains("[action_type:opengui] = modakbul_region_travel"), "guide region link missing");
        require(guide.contains("[action_type:back_to_last_screen] ="), "guide back action missing");

        String customGuis = Files.readString(config.resolve("custom_gui_screens.txt"), StandardCharsets.UTF_8);
        require(braceBalance(customGuis) == 0, "custom_gui_screens.txt: unbalanced braces");
        require(customGuis.contains("identifier = modakbul_region_travel"), "region custom GUI missing");
        require(customGuis.contains("identifier = modakbul_quick_guide"), "guide custom GUI missing");
        require(!customGuis.contains("title = 지역 이동"), "region native title must stay hidden");
        require(!customGuis.contains("title = 모닥불 이용 안내"), "guide native title must stay hidden");
        require(!containsMojibake(customGuis), "custom_gui_screens.txt: Korean text contains mojibake");

        validatePngAssets(config.resolve("assets"));
        System.out.println("FancyMenu validation passed: 3 layouts, 9 destinations, 15 UI assets");
    }

    private static void requireUniqueInstances(Path path, String content) {
        Matcher matcher = INSTANCE.matcher(content);
        Set<String> values = new HashSet<>();
        while (matcher.find()) {
            String id = matcher.group(1).trim();
            require(values.add(id), path + ": duplicate instance identifier " + id);
        }
    }

    private static void requireVanillaHidden(String content, String identifier) {
        Matcher blockMatcher = ELEMENT_BLOCK.matcher(content);
        while (blockMatcher.find()) {
            String block = blockMatcher.group(1);
            if (block.contains("instance_identifier = " + identifier)) {
                require(block.contains("is_hidden = true"), "vanilla widget must be hidden: " + identifier);
                return;
            }
        }
        throw new IllegalStateException("vanilla widget missing: " + identifier);
    }

    private static void requireAssetsExist(Path config, Path path, String content) {
        Matcher matcher = ASSET.matcher(content);
        while (matcher.find()) {
            String file = matcher.group(1).trim();
            require(Files.isRegularFile(config.resolve("assets").resolve(file)),
                path + ": missing local asset " + file);
        }
    }

    private static void requireActionsConnected(Path path, String content) {
        Set<String> actions = new HashSet<>();
        Matcher actionMatcher = ACTION.matcher(content);
        while (actionMatcher.find()) {
            require(actions.add(actionMatcher.group(1)), path + ": duplicate action " + actionMatcher.group(1));
        }

        Map<String, List<String>> blocks = new HashMap<>();
        Matcher blockMatcher = BLOCK.matcher(content);
        while (blockMatcher.find()) {
            String[] split = blockMatcher.group(2).split(";");
            blocks.put(blockMatcher.group(1), List.of(split).stream().filter(value -> !value.isBlank()).toList());
        }

        Matcher buttonMatcher = BUTTON_BLOCK.matcher(content);
        while (buttonMatcher.find()) {
            String block = buttonMatcher.group(1).trim();
            require(blocks.containsKey(block), path + ": button references missing block " + block);
        }

        Set<String> connected = new HashSet<>();
        for (Map.Entry<String, List<String>> block : blocks.entrySet()) {
            for (String action : block.getValue()) {
                require(actions.contains(action), path + ": block references missing action " + action);
                require(connected.add(action), path + ": action connected more than once " + action);
            }
        }
        require(connected.equals(actions), path + ": one or more actions are not connected");
    }

    private static void requireCustomButtonTextures(Path path, String content) {
        int customButtons = count(content, "element_type = custom_button");
        int normalTextures = count(content, "backgroundnormal = ");
        int hoverTextures = count(content, "backgroundhovered = ");
        int inactiveTextures = count(content, "background_texture_inactive = ");
        require(normalTextures >= customButtons, path + ": missing normal button texture");
        require(hoverTextures >= customButtons, path + ": missing hover button texture");
        require(inactiveTextures >= customButtons, path + ": missing inactive button texture");
    }

    private static void requireResponsiveLayout(Path path, String content) {
        int setScaleBlocks = 0;
        int autoScaleBlocks = 0;
        Matcher matcher = CUSTOMIZATION_BLOCK.matcher(content);
        while (matcher.find()) {
            String block = matcher.group(1);
            String action = property(block, "action");
            if ("setscale".equals(action)) {
                require("1.0".equals(property(block, "scale")),
                    path + ": responsive setscale must be 1.0");
                setScaleBlocks++;
            } else if ("autoscale".equals(action)) {
                require(Integer.toString(RESPONSIVE_BASE_WIDTH).equals(property(block, "basewidth")),
                    path + ": responsive autoscale basewidth mismatch");
                require(Integer.toString(RESPONSIVE_BASE_HEIGHT).equals(property(block, "baseheight")),
                    path + ": responsive autoscale baseheight mismatch");
                autoScaleBlocks++;
            }
        }
        require(setScaleBlocks == 1, path + ": expected exactly one responsive setscale block");
        require(autoScaleBlocks == 1, path + ": expected exactly one responsive autoscale block");
    }

    private static void requireFitsDefaultGui(Path path, String content, int screenWidth, int screenHeight) {
        Matcher blockMatcher = ELEMENT_BLOCK.matcher(content);
        while (blockMatcher.find()) {
            String block = blockMatcher.group(1);
            if (block.contains("is_hidden = true")) {
                continue;
            }
            String anchor = property(block, "anchor_point");
            if (!"top-centered".equals(anchor)) {
                continue;
            }
            int x = Integer.parseInt(property(block, "x"));
            int y = Integer.parseInt(property(block, "y"));
            int width = Integer.parseInt(property(block, "width"));
            int height = Integer.parseInt(property(block, "height"));
            int absoluteX = screenWidth / 2 + x;
            require(absoluteX >= 0, path + ": element starts left of default GUI: " + property(block, "instance_identifier"));
            require(y >= 0, path + ": element starts above default GUI: " + property(block, "instance_identifier"));
            require(absoluteX + width <= screenWidth,
                path + ": element exceeds default GUI width: " + property(block, "instance_identifier"));
            require(y + height <= screenHeight,
                path + ": element exceeds default GUI height: " + property(block, "instance_identifier"));
        }
    }

    private static void requireCanvasCoverage(Path path, String content, int screenWidth, int screenHeight) {
        Matcher blockMatcher = ELEMENT_BLOCK.matcher(content);
        while (blockMatcher.find()) {
            String block = blockMatcher.group(1);
            String identifier = property(block, "instance_identifier");
            if (!identifier.endsWith("-outer-panel")) {
                continue;
            }
            require("top-centered".equals(property(block, "anchor_point")),
                path + ": outer panel must use top-centered anchoring");
            int x = Integer.parseInt(property(block, "x"));
            int y = Integer.parseInt(property(block, "y"));
            int width = Integer.parseInt(property(block, "width"));
            int height = Integer.parseInt(property(block, "height"));
            int left = screenWidth / 2 + x;
            int right = screenWidth - left - width;
            int bottom = screenHeight - y - height;
            require(Math.abs(left - right) <= 1,
                path + ": outer panel is not horizontally centered");
            require(width * 10 >= screenWidth * 9,
                path + ": outer panel does not fill at least 90% of responsive canvas width");
            require(height * 10 >= screenHeight * 9,
                path + ": outer panel does not fill at least 90% of responsive canvas height");
            require(y >= 8 && bottom >= 8,
                path + ": outer panel needs a small vertical safety margin");
            return;
        }
        throw new IllegalStateException(path + ": outer panel missing");
    }

    private static String property(String block, String key) {
        Matcher matcher = Pattern.compile("(?m)^\\s*" + Pattern.quote(key) + "\\s*=\\s*([^\\r\\n]+)$").matcher(block);
        require(matcher.find(), "missing element property " + key);
        return matcher.group(1).trim();
    }

    private static void validatePngAssets(Path assets) throws Exception {
        List<String> icons = List.of(
            "icon_arena.png", "icon_casino.png", "icon_compass.png", "icon_exit.png",
            "icon_home.png", "icon_market.png", "icon_pokemon.png", "icon_settings.png",
            "icon_village.png"
        );
        List<String> textures = List.of(
            "ui_button.png", "ui_button_hover.png", "ui_button_inactive.png",
            "ui_button_selected.png", "ui_panel.png", "ui_panel_soft.png"
        );
        for (String file : icons) {
            BufferedImage image = ImageIO.read(assets.resolve(file).toFile());
            require(image != null, "unreadable PNG " + file);
            require(image.getWidth() == 128 && image.getHeight() == 128, "wrong icon dimensions " + file);
            require(((image.getRGB(0, 0) >>> 24) & 0xFF) == 0, "icon corner is not transparent " + file);
        }
        for (String file : textures) {
            BufferedImage image = ImageIO.read(assets.resolve(file).toFile());
            require(image != null, "unreadable PNG " + file);
            require(image.getWidth() == 64 && image.getHeight() == 64, "wrong texture dimensions " + file);
            require(((image.getRGB(0, 0) >>> 24) & 0xFF) == 0, "texture corner is not transparent " + file);
        }
        require(!Files.exists(assets.resolve("modakbul_menu_icons_atlas-source.png")),
            "source atlas must not ship to clients");
        require(!Files.exists(assets.resolve("modakbul_menu_icons_atlas.png")),
            "processed atlas must not ship to clients");
    }

    private static int braceBalance(String content) {
        int balance = 0;
        for (int index = 0; index < content.length(); index++) {
            if (content.charAt(index) == '{') {
                balance++;
            } else if (content.charAt(index) == '}') {
                balance--;
                require(balance >= 0, "closing brace appeared before opening brace");
            }
        }
        return balance;
    }

    private static boolean containsMojibake(String content) {
        return content.contains("\uFFFD")
            || content.contains("吏")
            || content.contains("媛")
            || content.contains("?대")
            || content.contains("?쒓");
    }

    private static int count(String content, String needle) {
        int result = 0;
        int offset = 0;
        while ((offset = content.indexOf(needle, offset)) >= 0) {
            result++;
            offset += needle.length();
        }
        return result;
    }

    private static void require(boolean condition, String message) {
        if (!condition) {
            throw new IllegalStateException(message);
        }
    }
}
