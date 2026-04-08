/**
 * Cloud Run Job entry point
 *
 * TASK_NAME environment variable determines which job to execute.
 * Add new jobs by adding cases to the switch statement.
 */

const taskName = process.env.TASK_NAME || "example";

async function runExampleJob(): Promise<void> {
  console.log("Running example job...");
  console.log(`Started at: ${new Date().toISOString()}`);

  // TODO: Replace with actual job logic
  await new Promise((resolve) => setTimeout(resolve, 1000));

  console.log("Example job completed successfully.");
}

async function main(): Promise<void> {
  console.log(`Executing job: ${taskName}`);

  switch (taskName) {
    case "example":
      await runExampleJob();
      break;
    default:
      console.error(`Unknown task: ${taskName}`);
      process.exit(1);
  }
}

main()
  .then(() => {
    console.log("Job finished successfully.");
    process.exit(0);
  })
  .catch((err) => {
    console.error("Job failed:", err);
    process.exit(1);
  });
