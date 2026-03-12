#include "config/ConfigReader.hpp"
#include "rendering/ParticleSystem.cuh"

#include <GLFW/glfw3.h>
#include <cstdio>
#include <cstdlib>
#include <cuda_runtime.h>
#include <filesystem>
#include <fstream>
#include <glad/gl.h>
#include <imgui.h>
#include <imgui_impl_glfw.h>
#include <imgui_impl_opengl3.h>
#include <sstream>
#include <string>

static void glfw_error_callback(int error, const char* description)
{
    std::fprintf(stderr, "GLFW Error %d: %s\n", error, description);
}

static std::string loadShaderSource(const char* filepath)
{
    std::ifstream file(filepath);
    if (!file.is_open())
    {
        std::fprintf(stderr, "Failed to open shader: %s\n", filepath);
        return "";
    }
    std::stringstream buffer;
    buffer << file.rdbuf();
    return buffer.str();
}

static unsigned int compileShader(unsigned int type, const char* source)
{
    unsigned int shader = glCreateShader(type);
    glShaderSource(shader, 1, &source, nullptr);
    glCompileShader(shader);

    int success;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &success);
    if (!success)
    {
        char infoLog[512];
        glGetShaderInfoLog(shader, 512, nullptr, infoLog);
        std::fprintf(stderr, "Shader compilation failed: %s\n", infoLog);
        glDeleteShader(shader);
        return 0;
    }
    return shader;
}

static unsigned int createShaderProgram(const char* vertPath, const char* fragPath)
{
    std::string vertSource = loadShaderSource(vertPath);
    std::string fragSource = loadShaderSource(fragPath);

    if (vertSource.empty() || fragSource.empty())
    {
        return 0;
    }

    unsigned int vertShader = compileShader(GL_VERTEX_SHADER, vertSource.c_str());
    unsigned int fragShader = compileShader(GL_FRAGMENT_SHADER, fragSource.c_str());

    if (!vertShader || !fragShader)
    {
        if (vertShader)
            glDeleteShader(vertShader);
        if (fragShader)
            glDeleteShader(fragShader);
        return 0;
    }

    unsigned int program = glCreateProgram();
    glAttachShader(program, vertShader);
    glAttachShader(program, fragShader);
    glLinkProgram(program);

    int success;
    glGetProgramiv(program, GL_LINK_STATUS, &success);
    if (!success)
    {
        char infoLog[512];
        glGetProgramInfoLog(program, 512, nullptr, infoLog);
        std::fprintf(stderr, "Shader linking failed: %s\n", infoLog);
        glDeleteProgram(program);
        program = 0;
    }

    glDeleteShader(vertShader);
    glDeleteShader(fragShader);

    return program;
}

int main([[maybe_unused]] int argc, char* argv[])
{
    // ------------------------------------------------------------------
    // Load configuration (fail-fast: config.toml must exist next to binary)
    // ------------------------------------------------------------------
    const auto binaryDir = std::filesystem::path{argv[0]}.parent_path();
    const auto configPath = (binaryDir / "config.toml").string();

    psim::config::ConfigReader cfg{};
    if (auto loadResult = cfg.load(configPath); !loadResult)
    {
        std::fprintf(stderr,
                     "Fatal: failed to load config.toml at '%s': %s\n",
                     configPath.c_str(),
                     loadResult.error().message.c_str());
        return EXIT_FAILURE;
    }

    // ------------------------------------------------------------------
    // Read framework parameters (getOrDefault guarantees startup on partial
    // configs while individual key errors are non-fatal).
    // ------------------------------------------------------------------
    const auto windowWidth = cfg.getOrDefault<int>("framework.window", "width", 1280);
    const auto windowHeight = cfg.getOrDefault<int>("framework.window", "height", 720);
    const auto windowTitle =
        cfg.getOrDefault<std::string>("framework.window", "title", "Particle Simulation Framework");
    const auto vsync = cfg.getOrDefault<bool>("framework", "vsync", true);
    const auto particleCount = static_cast<std::uint32_t>(cfg.getOrDefault<int>("model.sph", "particle_count", 100000));
    const auto initSpeed = cfg.getOrDefault<float>("framework", "simulation_speed", 1.0F);
    const auto bgR = cfg.getOrDefault<float>("framework.rendering", "background_r", 0.05F);
    const auto bgG = cfg.getOrDefault<float>("framework.rendering", "background_g", 0.05F);
    const auto bgB = cfg.getOrDefault<float>("framework.rendering", "background_b", 0.08F);

    glfwSetErrorCallback(glfw_error_callback);

    if (!glfwInit())
    {
        std::fprintf(stderr, "Failed to initialize GLFW\n");
        return EXIT_FAILURE;
    }

    // OpenGL 4.6 Core
    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 4);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 6);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);

    GLFWwindow* window = glfwCreateWindow(windowWidth, windowHeight, windowTitle.c_str(), nullptr, nullptr);
    if (!window)
    {
        std::fprintf(stderr, "Failed to create GLFW window\n");
        glfwTerminate();
        return EXIT_FAILURE;
    }

    glfwMakeContextCurrent(window);
    glfwSwapInterval(vsync ? 1 : 0);

    // Load OpenGL functions
    int version = gladLoadGL(glfwGetProcAddress);
    if (version == 0)
    {
        std::fprintf(stderr, "Failed to initialize GLAD\n");
        glfwDestroyWindow(window);
        glfwTerminate();
        return EXIT_FAILURE;
    }
    std::printf("OpenGL %d.%d\n", GLAD_VERSION_MAJOR(version), GLAD_VERSION_MINOR(version));

    // Print CUDA device info
    int cudaDevice;
    cudaDeviceProp deviceProp;
    cudaGetDevice(&cudaDevice);
    cudaGetDeviceProperties(&deviceProp, cudaDevice);
    std::printf("CUDA Device: %s\n", deviceProp.name);

    // Setup Dear ImGui
    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGuiIO& io = ImGui::GetIO();
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;

    ImGui::StyleColorsDark();

    ImGui_ImplGlfw_InitForOpenGL(window, true);
    ImGui_ImplOpenGL3_Init("#version 460");

    // Load particle shaders
    unsigned int particleShader = createShaderProgram("shaders/particle.vert", "shaders/particle.frag");
    if (!particleShader)
    {
        std::fprintf(stderr, "Failed to create particle shader program\n");
        // Continue anyway - will just not render particles
    }

    // Create VAO for particles
    unsigned int particleVAO = 0;
    glGenVertexArrays(1, &particleVAO);

    // Initialize particle system with CUDA-GL interop
    ParticleSystem particles;
    bool cudaInitialized = particleSystemInit(particles, particleCount);
    if (!cudaInitialized)
    {
        std::fprintf(stderr, "Failed to initialize particle system\n");
    }

    // Setup VAO with particle VBO
    if (cudaInitialized && particles.vbo)
    {
        glBindVertexArray(particleVAO);
        glBindBuffer(GL_ARRAY_BUFFER, particles.vbo);
        // float4: xy = position, zw = color/alpha
        glVertexAttribPointer(0, 4, GL_FLOAT, GL_FALSE, sizeof(float) * 4, nullptr);
        glEnableVertexAttribArray(0);
        glBindBuffer(GL_ARRAY_BUFFER, 0);
        glBindVertexArray(0);
    }

    // Enable point sprites and blending
    glEnable(GL_PROGRAM_POINT_SIZE);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    // Simulation state
    bool paused = false;
    float simulationSpeed = initSpeed;
    double lastTime = glfwGetTime();

    // Main loop
    while (!glfwWindowShouldClose(window))
    {
        glfwPollEvents();

        double currentTime = glfwGetTime();
        float dt = static_cast<float>(currentTime - lastTime);
        lastTime = currentTime;

        // Update particles
        if (cudaInitialized && !paused)
        {
            particleSystemUpdate(particles, dt * simulationSpeed);
        }

        ImGui_ImplOpenGL3_NewFrame();
        ImGui_ImplGlfw_NewFrame();
        ImGui::NewFrame();

        // Control panel
        ImGui::Begin("Particle Simulation");

        ImGui::Text("GPU: %s", deviceProp.name);
        ImGui::Text("Particles: %u", particleCount);
        ImGui::Text("FPS: %.1f", io.Framerate);

        ImGui::Separator();

        ImGui::Checkbox("Paused", &paused);
        ImGui::SliderFloat("Speed", &simulationSpeed, 0.1f, 5.0f);

        if (ImGui::Button("Reset"))
        {
            particleSystemDestroy(particles);
            cudaInitialized = particleSystemInit(particles, particleCount);

            if (cudaInitialized && particles.vbo)
            {
                glBindVertexArray(particleVAO);
                glBindBuffer(GL_ARRAY_BUFFER, particles.vbo);
                glVertexAttribPointer(0, 4, GL_FLOAT, GL_FALSE, sizeof(float) * 4, nullptr);
                glEnableVertexAttribArray(0);
                glBindBuffer(GL_ARRAY_BUFFER, 0);
                glBindVertexArray(0);
            }
        }

        ImGui::Separator();

        if (ImGui::Button("Exit"))
        {
            glfwSetWindowShouldClose(window, GLFW_TRUE);
        }

        ImGui::End();

        // Render
        int display_w, display_h;
        glfwGetFramebufferSize(window, &display_w, &display_h);
        glViewport(0, 0, display_w, display_h);
        glClearColor(bgR, bgG, bgB, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);

        // Draw particles
        if (cudaInitialized && particleShader && particles.vbo)
        {
            glUseProgram(particleShader);
            glBindVertexArray(particleVAO);
            glDrawArrays(GL_POINTS, 0, particles.count);
            glBindVertexArray(0);
            glUseProgram(0);
        }

        // Draw ImGui
        ImGui::Render();
        ImGui_ImplOpenGL3_RenderDrawData(ImGui::GetDrawData());

        glfwSwapBuffers(window);
    }

    // Cleanup
    particleSystemDestroy(particles);

    if (particleVAO)
        glDeleteVertexArrays(1, &particleVAO);
    if (particleShader)
        glDeleteProgram(particleShader);

    ImGui_ImplOpenGL3_Shutdown();
    ImGui_ImplGlfw_Shutdown();
    ImGui::DestroyContext();

    glfwDestroyWindow(window);
    glfwTerminate();

    return EXIT_SUCCESS;
}
